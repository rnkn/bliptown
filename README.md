# Bliptown

## Installation

Install required packages:

```
# pkg_add cmake gcc jq libqrencode png sqlports
```

Build required packages:

```
$ portgen cpan Carton
```

Install Bliptown app:

```
$ git clone /home/rnkn/git/bliptown.git
$ cd bliptown
$ carton install
$ doas install -m 755 -o root -g bin etc/rc.d/bliptown /etc/rc.d/
$ doas rcctl enable bliptown
$ doas rcctl start bliptown
```

Install optional packages:

```
# pkg_add emacs vim nano GraphicsMagick
```
