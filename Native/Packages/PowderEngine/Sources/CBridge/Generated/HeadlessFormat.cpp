#include <cstdint>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <optional>
#include <stdexcept>
#include "Format.h"
#include "graphics/VideoBuffer.h"

ByteString format::UnixtimeToDate(time_t unixtime, ByteString dateFormat, bool local)
{
	struct tm * timeData;
	char buffer[128];

	if (local)
	{
		timeData = localtime(&unixtime);
	}
	else
	{
		timeData = gmtime(&unixtime);
	}

	strftime(buffer, sizeof(buffer), dateFormat.c_str(), timeData);
	return ByteString(buffer);
}

ByteString format::UnixtimeToDateMini(time_t unixtime)
{
	time_t currentTime = time(nullptr);
	struct tm currentTimeData = *gmtime(&currentTime);
	struct tm timeData = *gmtime(&unixtime);

	if(currentTimeData.tm_year != timeData.tm_year)
	{
		return UnixtimeToDate(unixtime, "%d %b %Y");
	}
	else if(currentTimeData.tm_mon != timeData.tm_mon || currentTimeData.tm_mday != timeData.tm_mday)
	{
		return UnixtimeToDate(unixtime, "%d %B");
	}
	else
	{
		return UnixtimeToDate(unixtime, "%H:%M:%S");
	}
}

String format::CleanString(String dirtyString, bool ascii, bool color, bool newlines, bool numeric)
{
	for (size_t i = 0; i < dirtyString.size(); i++)
	{
		switch(dirtyString[i])
		{
		case '\b':
			if (color)
			{
				dirtyString.erase(i, 2);
				i--;
			}
			else
				i++;
			break;
		case '\x0E':
			if (color)
			{
				dirtyString.erase(i, 1);
				i--;
			}
			break;
		case '\x0F':
			if (color)
			{
				dirtyString.erase(i, 4);
				i--;
			}
			else
				i += 3;
			break;
		case '\r':
		case '\n':
			if (newlines)
				dirtyString[i] = ' ';
			break;
		default:
			if (numeric && (dirtyString[i] < '0' || dirtyString[i] > '9'))
			{
				dirtyString.erase(i, 1);
				i--;
			}
			// if less than ascii 20 or greater than ascii 126, delete
			else if (ascii && (dirtyString[i] < ' ' || dirtyString[i] > '~'))
			{
				dirtyString.erase(i, 1);
				i--;
			}
			break;
		}
	}
	return dirtyString;
}

std::vector<char> format::PixelsToPPM(PlaneAdapter<std::vector<pixel>> const &input)
{
	std::vector<char> data;
	ByteString header = ByteString::Build("P6\n", input.Size().X, " ", input.Size().Y, "\n255\n");
	data.insert(data.end(), header.begin(), header.end());

	data.reserve(data.size() + input.Size().X * input.Size().Y * 3);

	for (int i = 0; i < input.Size().X * input.Size().Y; i++)
	{
		auto colour = RGB::Unpack(input.data()[i]);
		data.push_back(colour.Red);
		data.push_back(colour.Green);
		data.push_back(colour.Blue);
	}

	return data;
}

// Native shells use platform image codecs; headless engine exposes OPS, not PNG.
std::unique_ptr<std::vector<char>> format::PixelsToPNG(PlaneAdapter<std::vector<pixel>> const &) { return nullptr; }
std::unique_ptr<PlaneAdapter<std::vector<pixel_rgba>>> format::PixelsFromPNG(std::span<const char>) { return nullptr; }
std::unique_ptr<PlaneAdapter<std::vector<pixel>>> format::PixelsFromPNG(std::span<const char>, RGB) { return nullptr; }

const static char hex[] = "0123456789ABCDEF";

ByteString format::Url::ToByteString() const
{
	ByteStringBuilder sb;
	sb << base;
	bool first = true;
	for (auto &[ key, value ] : params)
	{
		sb << (first ? '?' : '&') << key << "=" << format::URLEncode(value);
		first = false;
	}
	return sb.Build();
}

ByteString format::URLEncode(ByteString source)
{
	ByteString result;
	for (auto it = source.begin(); it < source.end(); ++it)
	{
		if (!((*it >= 'a' && *it <= 'z') ||
		      (*it >= 'A' && *it <= 'Z') ||
		      (*it >= '0' && *it <= '9')))
		{
			auto byte = uint8_t(*it);
			result.append(1, '%');
			result.append(1, hex[(byte >> 4) & 0xF]);
			result.append(1, hex[ byte       & 0xF]);
		}
		else
		{
			result.append(1, *it);
		}
	}
	return result;
}

ByteString format::URLDecode(ByteString source)
{
	ByteString result;
	for (auto it = source.begin(); it < source.end(); ++it)
	{
		if (*it == '%' && it + 2 < source.end())
		{
			auto byte = uint8_t(0);
			for (auto i = 0; i < 2; ++i)
			{
				it += 1;
				auto *off = strchr(hex, toupper(*it));
				if (!off)
				{
					return {};
				}
				byte = (byte << 4) | (off - hex);
			}
			result.append(1, byte);
		}
		else if (*it == '+')
		{
			result.append(1, ' ');
		}
		else
		{
			result.append(1, *it);
		}
	}
	return result;
}

void format::RenderTemperature(StringBuilder &sb, float temp, TempScale scale)
{
	switch (scale)
	{
	case TEMPSCALE_CELSIUS:
		sb << (temp - 273.15f) << "C";
		break;
	case TEMPSCALE_FAHRENHEIT:
		sb << (temp - 273.15f) * 1.8f + 32.0f << "F";
		break;
	default:
		sb << temp << "K";
		break;
	}
}

float format::StringToTemperature(String str, TempScale defaultScale)
{
	auto scale = defaultScale;
	if (str.size())
	{
		if (str.EndsWith("K"))
		{
			scale = TEMPSCALE_KELVIN;
			str = str.SubstrFromEnd(1);
		}
		else if (str.EndsWith("C"))
		{
			scale = TEMPSCALE_CELSIUS;
			str = str.SubstrFromEnd(1);
		}
		else if (str.EndsWith("F"))
		{
			scale = TEMPSCALE_FAHRENHEIT;
			str = str.SubstrFromEnd(1);
		}
	}
	if (!str.size())
	{
		throw std::out_of_range("empty string");
	}
	auto out = str.ToNumber<float>();
	switch (scale)
	{
	case TEMPSCALE_CELSIUS:
		out = out + 273.15;
		break;
	case TEMPSCALE_FAHRENHEIT:
		out = (out - 32.0f) / 1.8f + 273.15f;
		break;
	default:
		break;
	}
	return out;
}
