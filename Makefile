DIR = \
	`basename ${PWD}`

pkg: clean
	mkdir -p proto
	cat src/pkginfo.s | sed -e s/~PSTAMP~/`uname -n``date +%Y%m%d%H%M%S`/g > src/pkginfo
	pkgmk -f src/prototype -d proto -r src

clean:
	rm -rf proto/*
	if [ -d proto ] ; then \
		rmdir proto ; \
	fi

dist:
	hg revert --all
	tar cf ${DIR}.tar -C .. ${DIR}/Changelog -C .. ${DIR}/Makefile \
	-C .. ${DIR}/README.zfs-auto-snapshot.txt -C .. ${DIR}/src
	gzip ${DIR}.tar
