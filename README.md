Fugu

Fugu (河豚) script that, given a 2-letter ISO code, fetches routed ASNs ( from RIPEstat), pulls country IPv4 CIDRs ( from IPDeny), queries ASNMap per ASN (requiring PDCP API key), aggregates with mapcidr and outputs clean lists.


    USAGE

    bash fugu.sh -k YOUR_PDCP_API_KEY

    
