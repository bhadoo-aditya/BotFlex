##! This script analyzes inbound and outbound scanning activities.
##! Inbound scanning can be a very elementray sign of botnet infection. 
##! Outbound scan contributes to attack phase of botnet infection.
##! This script evokes events related to inbound and outbound scan.

@load botflex/utils/types
@load botflex/detection/scan/pre-scan

module BotflexScan;

export {
	## This script generates two logs, one for inbound and
	## another for outbound scannning
	redef enum Log::ID += { LOG_IB, LOG_OB };

	type Info_ib: record {
		ts:                time             &log;
		src_ip:            addr             &log;
		scan_type:         string	    &log;
		num_ports_scanned: count            &log;
		num_addrs_scanned: count            &log;
		target_port:	   port             &log;
		msg:		   string	    &log;
		victims:           string           &log;
		
	};

	type Info_ob: record {
		ts:                time             &log;
		src_ip:            addr             &log;
		scan_type:         string	    &log;
		num_ports_scanned: count            &log;
		num_addrs_scanned: count            &log;
		target_port:	   port             &log;
		msg:		   string	    &log;
		
	};
	
	redef record connection += {
	conn: Info_ib &optional;};

	redef record connection += {
	conn: Info_ob &optional;};

	## Event that can be handled to access the scan
	## record as it is sent on to the logging framework.
	global log_scan_ib: event(rec: Info_ib);
	global log_scan_ob: event(rec: Info_ob);

	## The event that sufficient evidence has been gathered to declare the inbound 
	## scan or attack (in case of outbound scan) phase of botnet infection lifecycle
	global scan_ib: event( victim: addr, weight: double );
	global scan_ob: event( src_ip: addr, weight: double );
	global log_scan: event( ts: time, src_ip: addr, scan_type: string, num_ports_scanned: count,
	       num_addrs_scanned: count, target_port: port, msg: string, victims: string, outbound: bool );

	## Weights of different events
	global weight_addr_scan = 0.8;
	global weight_addr_scan_critical = 1.0;
	global weight_port_scan = 0.25;
	# Threshold for scanning privileged ports.
	global weight_low_port_troll = 0.5;
}

event bro_init() &priority=5
	{
	Log::create_stream(BotflexScan::LOG_IB, [$columns=Info_ib, $ev=log_scan_ib]);
	Log::create_stream(BotflexScan::LOG_OB, [$columns=Info_ob, $ev=log_scan_ob]);
	}

event Input::end_of_data(name: string, source: string) 
	{
	if ( name == "config_stream" )
		{
		if ( "weight_addr_scan" in Config::table_config )
			weight_addr_scan = to_double(Config::table_config["weight_addr_scan"]$value);
		else
			print "Can't find BotflexScan::weight_addr_scan";

		if ( "weight_addr_scan_critical" in Config::table_config )
			weight_addr_scan_critical = to_double(Config::table_config["weight_addr_scan_critical"]$value);
		else
			print "Can't find BotflexScan::weight_addr_scan_critical";

		if ( "weight_port_scan" in Config::table_config )
			weight_port_scan = to_double(Config::table_config["weight_port_scan"]$value);
		else
			print "Can't find BotflexScan::weight_port_scan";
				
		if ( "weight_low_port_troll" in Config::table_config )
			weight_low_port_troll = to_double(Config::table_config["weight_low_port_troll"]$value);			
		else
			print "Can't find BotflexScan::weight_low_port_troll";		
		}
	}

global scan_ib_info: BotflexScan::Info_ib;
global scan_ob_info: BotflexScan::Info_ob;

## Hooking into notices of interest generated by pre-scan.bro
redef Notice::policy += {
       [$pred(n: Notice::Info) = {  
	       local t = network_time();

               if ( n$note == Scan::PortScan )
                       {
			local msg1 = fmt("%s: %s: Severity: %s",strftime(str_time, t),n$msg,n$sub);
			local outbound = Site::is_local_addr(n$src);
			
			if ( outbound )
				{
				event BotflexScan::scan_ob( n$src, weight_port_scan );
				event BotflexScan::log_scan(t, n$src, "Port Scan", n$n, 0, n$p, 
						              msg1, "", T );
				}
			else
				{
				event BotflexScan::scan_ib(n$src, weight_port_scan );
				event BotflexScan::log_scan(t, n$src, "Port Scan", n$n, 0, n$p, 
						              msg1, fmt("%s", n$dst), F );
				}
                       }

               else if ( n$note == Scan::AddressScanOutbound )
                       {
			local severity_ob = n$sub;

			if ( severity_ob == "Medium" )
				event BotflexScan::scan_ob( n$src, weight_addr_scan );
			else if ( severity_ob == "Critical" )
				event BotflexScan::scan_ob( n$src, weight_addr_scan_critical );

			local msg2 = fmt("%s: %s: Severity: %s",strftime(str_time, t),n$msg,n$sub);
			 
			event BotflexScan::log_scan(t, n$src, "Address Scan", 0, n$n, n$p, 
						      msg2, "", T );	
                       }

		else if ( n$note == Scan::AddressScanInbound )
                       {
			# n$msg has the form <the msg>:<victim1 victim2 victim3..>
			local msg_arr = split(n$msg, /[:]/);
			local str_victims = split( msg_arr[2], /[[:blank:]]*/ );

			for ( v in str_victims )
				{
				local severity_ib = n$sub;

				if ( severity_ib == "Medium" )
					event BotflexScan::scan_ib( n$src, weight_addr_scan );
				else if ( severity_ib == "Critical" )
					event BotflexScan::scan_ib( n$src, weight_addr_scan_critical );
				}

			event BotflexScan::log_scan(t, n$src, "Address Scan", n$n, 0, n$p, 
						      fmt("%s: %s",msg_arr[1], n$sub), msg_arr[2], F );

                       }

	       else if ( n$note == Scan::LowPortTrolling )
                       {
			local msg4 = fmt("%s: %s: Severity: %s",strftime(str_time, t),n$msg,n$sub);
			local outbound2 = Site::is_local_addr(n$src);

			if ( outbound2 )
				{
				event BotflexScan::scan_ob( n$src, weight_low_port_troll );
				event BotflexScan::log_scan(t, n$src, "Port Scan", n$n, 0, n$p, 
						      msg4, "", T );
				}
			else
				{
				event BotflexScan::scan_ib( n$src, weight_low_port_troll );
				event BotflexScan::log_scan(t, n$src, "Port Scan", n$n, 0, n$p, 
						      msg4, fmt("%s", n$dst), F );
				}
                       }
	
       }]
};


# Logging scan information. The last parameter <outbound> specifies which
# log the information will be written to
event log_scan( ts: time, src_ip: addr, scan_type: string, num_ports_scanned: count,
	       num_addrs_scanned: count, target_port: port, msg: string, victims: string, outbound: bool )
	{
	if ( outbound )
		{
		scan_ob_info$ts = ts;
		scan_ob_info$src_ip = src_ip;
		scan_ob_info$scan_type = scan_type;
		scan_ob_info$num_ports_scanned = num_ports_scanned;
		scan_ob_info$num_addrs_scanned = num_addrs_scanned;
		#scan_ob_info$target_port = target_port;
		scan_ob_info$msg = msg;

		Log::write(BotflexScan::LOG_OB, BotflexScan::scan_ob_info );
		}
	else
		{
		scan_ib_info$ts = ts;
		scan_ib_info$src_ip = src_ip;
		scan_ib_info$scan_type = scan_type;
		scan_ib_info$num_ports_scanned = num_ports_scanned;
		scan_ib_info$num_addrs_scanned = num_addrs_scanned;
		scan_ib_info$target_port = target_port;
		scan_ib_info$msg = msg;
		scan_ib_info$victims = victims;

		Log::write(BotflexScan::LOG_IB, BotflexScan::scan_ib_info );
		}
	}


