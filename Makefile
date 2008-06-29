pkg: clean
	mkdir -p proto
	pkgmk -f `pwd`/src/prototype -d `pwd`/proto -r `pwd`/src

clean:
	rm -rf proto/*
	rmdir proto
