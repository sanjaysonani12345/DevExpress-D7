//---------------------------------------------------------------------------
#include <vcl.h>
#pragma hdrstop
USERES("dcldxmdsc5.res");
USERES("dxmdsreg.dcr");
USEPACKAGE("vcl50.bpi");
USEPACKAGE("vcldb50.bpi");
USEPACKAGE("dxmdsC5.bpi");
USEUNIT("dxmdatps.pas");
USEUNIT("dxmdsreg.pas");
USEUNIT("dxmdseda.pas");
USEUNIT("dxmdsedt.pas");
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
