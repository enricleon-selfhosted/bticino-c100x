#!/bin/sh
# shellcheck shell=dash
firmware_url() {
    case "$1:$2" in
        C100X:1.5.8) echo "https://www.homesystems-legrandgroup.com/MatrixENG/liferay/bt_mxLiferayCheckout.jsp?fileFormat=generic&fileName=C100X_010508.fwz&fileId=58107.23188.17611.32784" ;;
        C100X:1.5.7) echo "https://www.homesystems-legrandgroup.com/MatrixENG/liferay/bt_mxLiferayCheckout.jsp?fileFormat=generic&fileName=C100X_010507.fwz&fileId=58107.23188.5954.54078" ;;
        C100X:1.5.5) echo "https://www.homesystems-legrandgroup.com/MatrixENG/liferay/bt_mxLiferayCheckout.jsp?fileFormat=generic&fileName=C100X_010505.fwz&fileId=58107.23188.62332.48840" ;;
        C100X:1.5.1) echo "https://www.homesystems-legrandgroup.com/MatrixENG/liferay/bt_mxLiferayCheckout.jsp?fileFormat=generic&fileName=C100X_010501.fwz&fileId=58107.23188.46381.34528" ;;
        *) echo "" ;;
    esac
}
firmware_md5() {
    case "$1:$2" in
        C100X:1.5.8) echo "0bdd681ac772b886767b4f5d792db3d3" ;;
        *) echo "" ;;
    esac
}
