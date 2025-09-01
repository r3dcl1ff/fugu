Fugu

Fugu (河豚) is a simple bash script that given a 2-letter ISO code, fetches routed ASNs ( from RIPEstat), pulls country IPv4 CIDRs ( from IPDeny), queries ASNMap per ASN (requiring Project Discovery Cloud API key, free tier), aggregates with mapcidr and outputs clean lists. The script essentially allows for eumeration of all IP addresses connected to a given country.
Use exclusively for research purposes , I am not responsible for any misuse of the script.API key available at: https://cloud.projectdiscovery.io/  


    USAGE

    bash fugu.sh -k YOUR_PDCP_API_KEY

    
