pkg: clean
	mkdir -p proto
	cat `pwd`/src/pkginfo.s | sed -e s/~PSTAMP~/`uname -n``date +%Y%m%d%H%M%S`/g > `pwd`/src/pkginfo
	pkgmk -f `pwd`/src/prototype -d `pwd`/proto -r `pwd`/src

clean:
	rm -rf proto/*
	rmdir proto
