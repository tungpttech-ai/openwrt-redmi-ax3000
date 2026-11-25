# Wi-Fi setup recovery

After OpenWrt finishes booting, release the WPS button three times within four seconds. Join `OpenWrt-Setup` and open [192.168.77.1](http://192.168.77.1/). Setup Wi-Fi closes after ten minutes and permits only DHCP and web access to the router. The image recreates its setup network after a factory reset.

Download the factory UBI and Image Builder from the [release matching this branch](https://github.com/hzyitc/openwrt-redmi-ax3000/releases/tag/ci-ipq50xx-qsdk-kernel-5.4-openwrt-21.02-qsdk-11.5.05.841.1029-20240727-173350-UTC). On Linux x86-64 with `uv` installed, extract the Image Builder and run from the repository root:

```sh
bash wps-setup/build.sh /path/to/imagebuilder /path/to/stock-factory.ubi /path/to/output
```

Choose the `redmi_ax3000` factory UBI for Redmi AX3000 or Xiaomi CR880x boards and the `cmcc_rax3000q` factory UBI for a CMCC RAX3000Q. The build identifies the stock image by its SHA-256 and reuses its kernel and packages. Check the physical model and board revision before installing a build. The two profiles report the same WPS GPIO under different button names. The CMCC profile uses short releases of the GPIO mapped to `reset` and retains its long-hold factory reset. The Redmi profile uses the WPS event and retains the original reset handler.

The build prompts for a WPA2 password. Set `WPS_SETUP_PASSWORD_FILE` to a private file containing a single password for a noninteractive build. The resulting firmware contains that password and should be handled accordingly.
