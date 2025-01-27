![Setup diagram](../openqa-qubesos-setup.png)

For details about how this setup works, see
[../adding-vnc-setup.md](../adding-vnc-setup.md).

### Start the job

While logged into openQA server (unless you've installed and configured
`openqa-cli` locally):

Perform installation:

```
openqa-cli api -X POST isos DISTRI=qubesos VERSION=4.2 FLAVOR=install-iso-supermicro ARCH=x86_64 BUILD=4.2.0
```

ISO name is generated as `ISO=Qubes-R%BUILD%-%ARCH%.iso`, you should also create
a symlink to it in `hdd` directory.  Only Fedora template is going to be
installed to make setup faster.

Output like

```
{"count":4,"failed":[],"ids":[448,449,450,451],"scheduled_product_id":59}
```

means the jobs (`4` in this case) were scheduled successfully.

Use "Dependencies" tab to see jobs which are part of the same run.

### Verify the job

Because things sometimes don't work as expected, it's better to check that it
was able to start instead of incorrectly assuming that it did and seeing a quick
failure after coming back in half an hour.

Go to <http://openqa/tests>, open the running job and see that video is there
maybe in a minute or two after starting the job.  Restart the job if it has
failed to start for no good reason or video isn't working.
