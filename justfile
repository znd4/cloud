xhs-dnsimple path *args:
    @xhs \
        https://api.dnsimple.com/v2{{ path }} \
        {{ args }} \
        Authorization:"Bearer $DNSIMPLE_TOKEN" \
