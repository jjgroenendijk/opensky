// Wine's own msvcp140.dll does not export `__crtLCMapStringA`, which the static regex
// helpers in MSVC's msvcprt.lib call. Defining it here keeps the import out of the DLL.
// Signature: microsoft/STL, stl/src/StlLCMapStringA.cpp (Apache-2.0 WITH LLVM-exception).

extern "C" {
__declspec(dllimport) unsigned long __stdcall
LocaleNameToLCID(const wchar_t *name, unsigned long flags);
__declspec(dllimport) int __stdcall LCMapStringA(
    unsigned long locale,
    unsigned long flags,
    const char *source,
    int sourceCount,
    char *destination,
    int destinationCount);

int __cdecl __crtLCMapStringA(
    const wchar_t *localeName,
    unsigned long flags,
    const char *source,
    int sourceCount,
    char *destination,
    int destinationCount,
    int,
    int) noexcept
{
    return LCMapStringA(
        LocaleNameToLCID(localeName, 0), flags, source, sourceCount, destination, destinationCount);
}
}
