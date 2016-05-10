
#include <stdio.h>
#include <stdlib.h>
#include "cuda.h"
#include <iostream>
#include <vlc>
#include <stdargs.h>
CUdevice    device;
CUmodule    cudaModule;
CUcontext   context;
CUfunction  function;
char * helloworld;
int vlc(){
helloworld="Hello world!";

printf(helloworld);

return 0;
}
int main(void) { return vlc(); }