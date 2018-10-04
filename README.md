rc\_visard Offboard Data Recording Scripts
=================================

This repository provides Linux and Windows scripts for recording data with the rc\_visard.

Linux
-----

Only the file `rc_visard_record.sh` is required. The dependencies `rc_genicam_api` and ` rc_dynamics_api` must be installed.

Usage:

```
./rc_visard_record.sh [options] <rc_visard_id>
```

Windows
-------

Download or clone the entire repository, since the dependencies are bundled with the script.

Either double-click `rc_visard_record.bat` or use the following command line:

```
rc_visard_record.bat [options] <rc_visard_id>
```

