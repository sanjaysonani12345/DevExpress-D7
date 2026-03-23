//---------------------------------------------------------------------------
#include <vcl.h>
#pragma hdrstop
USERES("dxmdsc5.res");
USEPACKAGE("vcl50.bpi");
USEUNIT("dxmdaset.pas");
USEPACKAGE("vcldb50.bpi");
//---------------------------------------------------------------------------
#pragma package(smart_init)
//---------------------------------------------------------------------------
//   Package source.
//---------------------------------------------------------------------------
int WINAPI DllEntryPoint(HINSTANCE hinst, unsigned long reason, void*)
{
    return 1;
}
//---------------------------------------------------------------------------
