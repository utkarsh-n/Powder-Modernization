# PocketFFT dependency

The unmodified `pocketfft_hdronly.h` and `LICENSE.md` are vendored from Martin
Reinecke's official contribution repository:

https://github.com/mreineck/pocketfft/tree/c90e55b3d529f8efa40ed01a20de22405f45fc65

Revision: `c90e55b3d529f8efa40ed01a20de22405f45fc65` (cpp branch, retrieved 2026-10-02).
License: BSD 3-Clause; retain and distribute LICENSE.md and the copyright notices
in the header. The header contains additional contributor notices.

TPTGravity.cpp adapts The Powder Toy 100.1.400 GPL gravity/Fft.cpp algorithm to
this portable C++ header, preserving its doubled grid, Fourier normalization,
inverse-square vector kernel, masks, and asynchronous exchange. No FFTW runtime
or platform-specific FFT binary is required. PocketFFT's internal pool is
disabled: each enabled simulation uses one worker owned by the gravity adapter.
