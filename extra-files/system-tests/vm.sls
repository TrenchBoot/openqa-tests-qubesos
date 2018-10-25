vm-packages:
  pkg.installed:
    - pkgs:
      - dnsmasq
{% if grains['os'] == 'Fedora' %}
      - redhat-rpm-config
      - python3-devel
      - nmap-ncat
{% else %}
      - libudev-dev
{% endif %}
      - qubes-input-proxy-sender
      - qubes-gpg-split-tests
      - qubes-usb-proxy
      - qubes-usb-proxy
      - usbutils
      - createrepo
      - python3-pip
      - xdotool
      - gcc
      - pulseaudio-utils

# broken on Fedora 24, lets install using pip (tests will handle that)
python-uinput:
  pkg.removed: []
