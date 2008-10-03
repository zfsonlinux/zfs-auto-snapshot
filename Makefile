DIR = \
	`basename ${PWD}`
ZFS_AUTO_SNAPSHOT_CHANGESET = \
	`hg identify`

pkg: clean
	mkdir -p proto
	find src | cpio -pvdum proto
	cat src/lib/svc/method/zfs-auto-snapshot | sed -e "s/~ZFS_AUTO_SNAPSHOT_CHANGESET~/${ZFS_AUTO_SNAPSHOT_CHANGESET}/g" > proto/src/lib/svc/method/zfs-auto-snapshot
	pkgmk -f proto/src/prototype -p `uname -n``date +%Y%m%d%H%M%S` -d proto -r proto/src

clean:
	rm -rf proto/*
	if [ -d proto ] ; then \
		rmdir proto ; \
	fi

dist: clean
	hg revert --all
	tar cf ${DIR}.tar -C .. ${DIR}/Changelog -C .. ${DIR}/Makefile \
	-C .. ${DIR}/README.zfs-auto-snapshot.txt -C .. ${DIR}/src
	gzip ${DIR}.tar
