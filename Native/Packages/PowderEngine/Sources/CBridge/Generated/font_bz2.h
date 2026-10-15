
#pragma once
#include <array>
#include <span>

extern const struct font_bz2Resource
{
	std::array<unsigned char, 57718> data;

	std::span<const char> AsCharSpan() const
	{
		return std::span(reinterpret_cast<const char *>(data.data()), data.size());
	}

	std::span<const unsigned char> AsUcharSpan() const
	{
		return std::span(data.data(), data.size());
	}
} font_bz2;
