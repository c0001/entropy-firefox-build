.PHONY: build build-without-optimization
build:
	env MK_OPT_NO_OPTIMIZATION=  bash entropy-make-via-docker.sh

build-without-optimization:
	env MK_OPT_NO_OPTIMIZATION=1 bash entropy-make-via-docker.sh
