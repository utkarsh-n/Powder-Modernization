# Third-party notices

Powder native 0.3 includes the software below. Source notices and license texts remain in their original vendor locations. The full GNU GPL version 3 text is also provided in [LICENSE](LICENSE).

## The Powder Toy

Copyright belongs to The Powder Toy contributors. The original simulation, element implementations, save parser/writer and supporting graphics/data code are reused under the project's GNU GPL license. Historical source headers specify GPL version 3 or later; preserve per-file notices. This project includes actual upstream source, not only a behavioral reimplementation.

- Repository: https://github.com/The-Powder-Toy/The-Powder-Toy
- Release: `v100.1.400`
- Peeled source commit: `d768aeb89acad986bd252d7e904bf44bb374545f`
- Annotated tag object: `c8be5165b7289706e17473bcfb38de112e78f140`
- Source archive SHA-256: `75cd971e1b2d6789f9e35b75926b76d037a564ad9291fa852ad9996c8ac40c96`
- Source and notices: [vendored tree](Packages/PowderEngine/Sources/CBridge/Upstream/), [COPYING](Packages/PowderEngine/COPYING), [modifications](Packages/PowderEngine/UPSTREAM.md), [machine-readable provenance](Packages/PowderEngine/UPSTREAM.json).

Local changes include the C/Swift adapters, portable FFT backend, headless build resources, bounded save handling and optional historical fusion behavior. The original SDL frontend, Lua and online services are retained as source provenance but are not compiled into this app. The original software renderer remains linked where engine callbacks and tables require it; native presentation uses Metal.

## JsonCpp 1.9.6

Copyright (c) 2007–2010 Baptiste Lepilleur and The JsonCpp Authors. The vendored license offers public-domain/MIT terms as described below. Source: https://github.com/open-source-parsers/jsoncpp. [Retained license](Packages/PowderEngine/Sources/JsonCpp/LICENSE).

```text
The JsonCpp library's source code, including accompanying documentation,
tests and demonstration applications, are licensed under the following
conditions...

Baptiste Lepilleur and The JsonCpp Authors explicitly disclaim copyright in all
jurisdictions which recognize such a disclaimer. In such jurisdictions,
this software is released into the Public Domain.

In jurisdictions which do not recognize Public Domain property (e.g. Germany as of
2010), this software is Copyright (c) 2007-2010 by Baptiste Lepilleur and
The JsonCpp Authors, and is released under the terms of the MIT License (see below).

In jurisdictions which recognize Public Domain property, the user of this
software may choose to accept it either as 1) Public Domain, 2) under the
conditions of the MIT License (see below), or 3) under the terms of dual
Public Domain/MIT License conditions described here, as they choose.

The MIT License is about as close to Public Domain as a license can get, and is
described in clear, concise terms at:

   http://en.wikipedia.org/wiki/MIT_License

The full text of the MIT License follows:

========================================================================
Copyright (c) 2007-2010 Baptiste Lepilleur and The JsonCpp Authors

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use, copy,
modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
========================================================================
(END LICENSE TEXT)

The MIT license is compatible with both the GPL and commercial
software, affording one all of the rights of Public Domain with the
minor nuisance of being required to keep the above copyright notice
and license text in the source code. Note also that by accepting the
Public Domain "license" you can re-license your copy using whatever
license you like.
```

## pocketfft

Martin Reinecke's pocketfft, revision `c90e55b3d529f8efa40ed01a20de22405f45fc65`, from https://github.com/mreineck/pocketfft. The vendored header SHA-256 is `3e9a05318d8e3b1446bda1c4617e6a103cdd23599ae0a776a92a6e8800e92fdc`. Its BSD 3-Clause license and additional header contributor notices remain intact. See [NOTICE](Packages/PowderEngine/Sources/CBridge/PocketFFT/NOTICE.md), [header](Packages/PowderEngine/Sources/CBridge/PocketFFT/pocketfft_hdronly.h) and [license](Packages/PowderEngine/Sources/CBridge/PocketFFT/LICENSE.md).

```text
Copyright (C) 2010-2018 Max-Planck-Society
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this
  list of conditions and the following disclaimer in the documentation and/or
  other materials provided with the distribution.
* Neither the name of the copyright holder nor the names of its contributors may
  be used to endorse or promote products derived from this software without
  specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Upstream image resampler

The compiled upstream resampler retains its Unlicense/public-domain dedication in [resampler.h](Packages/PowderEngine/Sources/CBridge/Upstream/resampler/resampler.h). Its notices and changelog remain in the source.

```text
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <http://unlicense.org/>
```

## Platform libraries

The app links Apple's system frameworks and the platform bzip2 library. It does not vendor an FFTW runtime, SDL runtime, Lua runtime or OpenAI SDK. Cloud access uses Foundation URLSession; on-device generation uses Apple's Foundation Models framework. Their presence does not replace the source licenses above.
