// Portable Newtonian gravity backend for The Powder Toy 100.1.400.
// Derived from upstream simulation/gravity/Fft.cpp (GPL-3.0-or-later).
// The convolution kernel, double-size padding, mask behavior, and asynchronous
// exchange are retained. pocketfft replaces FFTW; see PocketFFT/NOTICE.md.
#include "simulation/gravity/Gravity.h"
#include "TPTGravity.hpp"
#include "SimulationConfig.h"
#define POCKETFFT_NO_MULTITHREADING
#define POCKETFFT_CACHE_SIZE 8
#include "PocketFFT/pocketfft_hdronly.h"
#include <algorithm>
#include <cmath>
#include <complex>
#include <condition_variable>
#include <cstring>
#include <exception>
#include <mutex>
#include <thread>
#include <vector>

namespace {
constexpr auto blocks = CELLS * 2;
constexpr size_t realSize = blocks.X * blocks.Y;
constexpr size_t complexSize = (blocks.X / 2 + 1) * blocks.Y;
// pocketfft, like FFTW, is unnormalized when fct = 1.
constexpr float scaleFactor = -float(M_GRAV) / (NCELL * 4);
const pocketfft::shape_t shape{size_t(blocks.Y), size_t(blocks.X)};
const pocketfft::shape_t axes{0, 1};
const pocketfft::stride_t realStrides{blocks.X * ptrdiff_t(sizeof(float)), sizeof(float)};
const pocketfft::stride_t complexStrides{
    (blocks.X / 2 + 1) * ptrdiff_t(sizeof(std::complex<float>)), sizeof(std::complex<float>)};

void forward(const std::vector<float> &input, std::vector<std::complex<float>> &output) {
    pocketfft::r2c(shape, realStrides, complexStrides, axes, pocketfft::FORWARD,
                  input.data(), output.data(), 1.f, 1);
}

void inverse(const std::vector<std::complex<float>> &input, std::vector<float> &output) {
    pocketfft::c2r(shape, complexStrides, realStrides, axes, pocketfft::BACKWARD,
                  input.data(), output.data(), 1.f, 1);
}

struct PortableGravity final : Gravity {
    std::vector<float> massBig, forceXBig, forceYBig;
    std::vector<std::complex<float>> kernelXT, kernelYT, massBigT, forceXBigT, forceYBigT;
    GravityInput input;
    GravityOutput output;
    bool initialized = false;
    bool copyOutput = false;
    bool working = false;
    bool stopping = false;
    std::exception_ptr workerError;
    std::mutex mutex;
    std::condition_variable condition;
    std::thread worker;

    ~PortableGravity() {
        if (!worker.joinable()) { return; }
        {
            std::unique_lock lock(mutex);
            condition.wait(lock, [this] { return !working; });
            stopping = true;
        }
        condition.notify_one();
        worker.join();
    }

    void initialize() {
        if (initialized) { return; }
        massBig.assign(realSize, 0.f);
        forceXBig.resize(realSize);
        forceYBig.resize(realSize);
        kernelXT.resize(complexSize);
        kernelYT.resize(complexSize);
        massBigT.resize(complexSize);
        forceXBigT.resize(complexSize);
        forceYBigT.resize(complexSize);
        std::vector<float> kernelXRaw(realSize), kernelYRaw(realSize);
        auto kernelX = MakePlane<blocks.X, blocks.Y>(blocks, kernelXRaw.data());
        auto kernelY = MakePlane<blocks.X, blocks.Y>(blocks, kernelYRaw.data());
        for (auto position : blocks.OriginRect()) {
            const auto offset = position - CELLS;
            if (offset == Vec2{0, 0}) { continue; }
            const float distance = std::hypot(float(offset.X), float(offset.Y));
            const float denominator = std::pow(distance, 3.f);
            kernelX[position] = scaleFactor * offset.X / denominator;
            kernelY[position] = scaleFactor * offset.Y / denominator;
        }
        forward(kernelXRaw, kernelXT);
        forward(kernelYRaw, kernelYT);
        worker = std::thread([this] { run(); });
        initialized = true;
    }

    void wait() {
        std::unique_lock lock(mutex);
        condition.wait(lock, [this] { return !working; });
        if (workerError) { std::rethrow_exception(workerError); }
    }

    void dispatch() {
        {
            std::lock_guard lock(mutex);
            working = true;
        }
        condition.notify_one();
    }

    void calculate() {
        auto mass = MakePlane<blocks.X, blocks.Y>(blocks, massBig.data());
        for (auto position : CELLS.OriginRect()) {
            mass[position + CELLS] = input.mask[position] ? input.mass[position] : 0.f;
        }
        forward(massBig, massBigT);
        for (size_t index = 0; index < complexSize; ++index) {
            forceXBigT[index] = massBigT[index] * kernelXT[index];
            forceYBigT[index] = massBigT[index] * kernelYT[index];
        }
        inverse(forceXBigT, forceXBig);
        inverse(forceYBigT, forceYBig);
        auto forceX = MakePlane<blocks.X, blocks.Y>(blocks, forceXBig.data());
        auto forceY = MakePlane<blocks.X, blocks.Y>(blocks, forceYBig.data());
        for (auto position : CELLS.OriginRect()) {
            output.forceX[position] = input.mask[position] ? forceX[position] : 0.f;
            output.forceY[position] = input.mask[position] ? forceY[position] : 0.f;
        }
    }

    void run() noexcept {
        while (true) {
            {
                std::unique_lock lock(mutex);
                condition.wait(lock, [this] { return working || stopping; });
                if (stopping) { return; }
            }
            std::exception_ptr error;
            try { calculate(); } catch (...) { error = std::current_exception(); }
            {
                std::lock_guard lock(mutex);
                workerError = error;
                working = false;
            }
            condition.notify_one();
        }
    }
};
}

void Gravity::Exchange(GravityOutput &gravOut, GravityInput &gravIn, bool forceRecalc) {
    auto &solver = *static_cast<PortableGravity *>(this);
    solver.initialize();
    solver.wait();
    if (solver.copyOutput) {
        solver.copyOutput = false;
        std::swap(gravOut, solver.output);
    }
    if (forceRecalc ||
        std::memcmp(&solver.input.mass[{0, 0}], &gravIn.mass[{0, 0}], NCELL * sizeof(float)) ||
        std::memcmp(&solver.input.mask[{0, 0}], &gravIn.mask[{0, 0}], NCELL * sizeof(uint32_t))) {
        solver.copyOutput = true;
        std::swap(gravIn.mass, solver.input.mass);
        solver.input.mask = gravIn.mask;
        solver.dispatch();
    }
}

GravityPtr Gravity::Create() { return GravityPtr(new PortableGravity()); }

void GravityDeleter::operator()(Gravity *pointer) const {
    delete static_cast<PortableGravity *>(pointer);
}

void tpt_copy_gravity_state(Gravity &source, Gravity &destination) {
    auto &from = static_cast<PortableGravity &>(source);
    auto &to = static_cast<PortableGravity &>(destination);
    if (!from.initialized) { return; }
    from.wait();
    to.initialize();
    to.wait();
    to.input = from.input;
    to.output = from.output;
    to.copyOutput = from.copyOutput;
}
