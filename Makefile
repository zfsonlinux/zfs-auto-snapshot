DIR = \
	`basename ${PWD}`
ZFS_AUTO_SNAPSHOT_CHANGESET = \
	`hg identify`

pkg: clean
	mkdir -p proto
	find src | cpio -pvdum proto
	# we tag the method script during the build, which will
	# only happen if we're building from the original hg source,
	# not from the dist tarball - see the dist: target.
	cat src/lib/svc/method/zfs-auto-snapshot | sed -e "s/~ZFS_AUTO_SNAPSHOT_CHANGESET~/${ZFS_AUTO_SNAPSHOT_CHANGESET}/g" > proto/src/lib/svc/method/zfs-auto-snapshot
	pkgmk -f proto/src/prototype -p `uname -n``date +%Y%m%d%H%M%S` -d proto -r proto/src

clean:
	rm -rf proto/*
	if [ -d proto ] ; then \
		rmdir proto ; \
	fi

dist: clean
	# save off a copy of the method script before tagging it
	cp src/lib/svc/method/zfs-auto-snapshot zfs-auto-snapshot.src

	cat src/lib/svc/method/zfs-auto-snapshot | sed -e "s/~ZFS_AUTO_SNAPSHOT_CHANGESET~/${ZFS_AUTO_SNAPSHOT_CHANGESET}/g" > src/lib/svc/method/tagged-method-script
	mv src/lib/svc/method/tagged-method-script src/lib/svc/method/zfs-auto-snapshot
	grep "zfs-auto-snapshot changeset" src/lib/svc/method/zfs-auto-snapshot
	tar cf ${DIR}.tar -C .. ${DIR}/Changelog -C .. ${DIR}/Makefile \
	-C .. ${DIR}/README.zfs-auto-snapshot.txt -C .. ${DIR}/src
	gzip ${DIR}.tar
	
	# drop our saved method script back where we left it
	cp zfs-auto-snapshot.src src/lib/svc/method/zfs-auto-snapshot
