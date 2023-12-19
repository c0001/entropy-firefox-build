.PHONY: clean build build-without-optimization test

clean:
	@bash -c "set -e; if [ -d .git ]                                                ; \
		then echo 'In-git-mode'                                                       ; \
			git reset --hard HEAD                                                       ; \
			git clean -xfd .                                                            ; \
		fi"

build: clean
	env MK_TESTP= MK_OPT_NO_OPTIMIZATION=  bash entropy-make-via-docker.sh

build-without-optimization: clean
	env MK_TESTP= MK_OPT_NO_OPTIMIZATION=1 bash entropy-make-via-docker.sh

test:
	env MK_TESTP=test bash entropy-make-via-docker.sh
