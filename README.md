# Bliptown

## Installation

```sh
$ portgen cpan Carton
$ git clone /home/rnkn/git/bliptown.git
$ cd bliptown
$ carton install
$ doas install -m 755 -o root -g bin etc/rc.d/bliptown /etc/rc.d/
$ doas rcctl enable bliptown
$ doas rcctl start bliptown
```
