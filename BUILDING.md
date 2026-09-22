# Build from source

Install Python 3 and NASM. Run this command from the source directory:

```console
python scripts/build.py --resident-audio
```

The output files are `build/UCDD.EXE` and `build/UCDDSET.EXE`. The driver contains the internal audio host. The build does not download dependencies.

For a CD driver without resident audio, omit `--resident-audio`.

The release source archive contains the project source and this build script. Install DOS, a memory manager, and a CD redirector separately. No third-party programs are included.
