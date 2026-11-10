RT ?= $(CURDIR)/../../vendor/rknn3-toolkit-v1.2.0-x86_64/rknn3-api
rk-smi: rk-smi.c
	gcc -O2 -Wall -o $@ $< -I$(RT)/include -L$(RT)/lib -lrknn3_api -Wl,-rpath,$(RT)/lib
