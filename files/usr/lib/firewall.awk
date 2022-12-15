# Copyright (C) 2006 OpenWrt.org

BEGIN {
	FS=":"
}

($1 == "accept") || ($1 == "drop") || ($1 == "forward") {
	delete _opt
	str2data($3)
	if ((_l["proto"] == "") && (_l["sport"] _l["dport"] != "")) {
		_opt[0] = " -p tcp"
		_opt[1] = " -p udp"
	} else {
		_opt[0] = ""
	}
}

($1 == "accept") {
        print "#\n# rules for " $_
	target = " -j ACCEPT"
	for (o in _opt) {
		print "iptables -t nat -A prerouting_" $2 _opt[o] str2ipt($3) target
		# this one is to allow LAN access to node services when a DMZ server is in use
		if ($2 == "wifi") print "iptables -t nat -A PREROUTING " _opt[o] str2ipt($3) target
		print "iptables        -A input_" $2 "     " _opt[o] str2ipt($3) target
	}
}

($1 == "drop") {
        print "#\n# rules for " $_
	for (o in _opt) {
		print "iptables -t nat -A prerouting_" $2 _opt[o] str2ipt($3) " -j DROP"
	}
}

#    1      2                    3                       4      5
# forward:wifi:dport=80 proto=tcp dest=10.122.140.13:172.27.0.5:80

($1 == "forward") {
        print "#\n# rules for " $_
	target = " -j DNAT --to " $4
	fwopts = ""
	if ($5 != "") {
		if ((_l["proto"] == "tcp") || (_l["proto"] == "udp") || (_l["proto"] == "")) {
			if (_l["proto"] != "") fwopts = " -p " _l["proto"]
			fwopts = fwopts " --dport " $5
			target = target ":" $5
		}
		else fwopts = ""
	}
	for (o in _opt) {
		print "iptables -t nat -A prerouting_" $2 _opt[o] str2ipt($3) target
		# everything seems to work without this rule
		#print "iptables        -A forwarding_" $2 _opt[o] " -d " $4 fwopts " -j ACCEPT"

		# the wan is more restricted so it needs extra rules
		if($2 == "wan") {
		    fwopts = _opt[o]
		    if ((_l["proto"] != "") && (_opt[0] == "")) fwopts = " -p " _l["proto"]
		    if(_l["dport"] ~ /-/) {
			dport = portstr("dst", _l["dport"])
			print "iptables        -A input_" $2 fwopts " -d " $4 dport " -j ACCEPT"
		    } else {
			print "iptables        -A input_" $2 fwopts " -d " $4 " --dport " $5 " -j ACCEPT"
		    }
		}

		# rules to give lan hosts access to port forwarded services
		if ($2 == "wifi") {
		    fwopts = _opt[o]
		    dport = ""
		    if ((_l["proto"] != "") && (_opt[0] == "")) fwopts = " -p " _l["proto"]
		    if (_l["dport"] != "") dport = portstr("dst", _l["dport"])
		    print "iptables -t nat -A PREROUTING " fwopts " -s " LAN_NET " -d " _l["dest"] dport target
		}
	}

	# nat the packet source for requests that came from the lan
	# this doesn't work for the wan yet
	if ($2 == "wifi") {
	    print "iptables -t nat -A POSTROUTING -s " LAN_NET " -d " $4 " -j SNAT --to " _l["dest"]
	}
}
