# Third-party notices

Cool Head has no third-party code dependencies. It uses material from one project:

## System Sentinel

The list of security, device management and VPN products in `Sources/CoolHeadCore/Protected.swift` (product names and the identifiers that recognise them) comes from System Sentinel's `SecurityAgents.swift`, https://github.com/andrewbakercloudscale/system-sentinel. The way `Sources/CoolHeadCore/GPU.swift` measures each app's use of the graphics chip (the `accumulatedGPUTime` in the `AppUsage` of each IOAccelerator user client, and its `IOUserClientCreator`) follows System Sentinel's approach. Both are used under the MIT License:

```
MIT License

Copyright (c) 2026 Andrew Baker

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
