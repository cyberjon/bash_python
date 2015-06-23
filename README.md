# Bash: Python
Collection of script to help install, uninstall, and download Python and Python development enviroment.

## Usage

###1. Python

* Install Python

```
sudo ./install_python_deb.sh -i [-v <VERSION>]
```

* Uninstall Python

```
sudo ./install_python_deb.sh -u [-v <VERSION>]
```
* Download Python Package only

```
sudo ./install_python_deb.sh -d [-v <VERSION>]
```

###2. Python Development Environment

* Install Python Dev

```
sudo ./install_python_dev_deb.sh -i [-v <VERSION>]
```

* Uninstall Python Dev

```
sudo ./install_python_dev_deb.sh -u [-v <VERSION>]
```

* Download Python Dev Only

```
sudo ./install_python_dev_deb.sh -d [-v <VERSION>]
```

## Verified in 
* Ubuntu 14.04.x

## Known Issues
If you discover any bugs, feel free to create an issue on GitHub fork and send us a pull request.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License
Copyright © 2015 Clark Hsu

Licensed under the [Apache License, Version 2.0] [Apache].

Distributed under the [MIT License] [mit].

[Apache]: http://www.apache.org/licenses/LICENSE-2.0
[MIT]: http://www.opensource.org/licenses/mit-license.php
