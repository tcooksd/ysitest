#!/bin/bash

password=`cat /etc/nova/nova.conf  | grep mysql  | sed  's/:/ /g' | sed 's/@/ /g' | awk '{print $3}'`

arg1="$2"


return_statement ()
	{
echo "usage: [--list_open_virt_interfaces] [--list_uuid_to_host]"
echo "[--clean_failed_instance][--instance_info][--create_instance_vnc_forward_syntax]"
echo "error: too few arguments"
	}

clean_mysql ()
#sets virtual server records on nova mysql database to deleted manually. 
#expects args: $instance_id 
#passed in from function instance_info 
#still need to actually set the command, currently just creates script to run. 

	{
	echo "run command \"mysql --password=$password -u nova -h 172.23.196.82  nova -e \"update instances SET updated_at=NOW(), deleted=\"1\", vm_state=\"deleted\", terminated_at=NOW() where uuid=$1\""
	
	if [ $? -ne "0" ]
		then 
			echo "something went wrong"
	else
		echo "your instance should be clean"
	fi
	}

get_virsh_info ()
#first verifies if virtual machine is still running. 
#second provides options to manually loging to physical server and destroy instance 
#or attempt to destroy through nova
#expects args:  $server_hosting $local_name $instance_id $vm_name 
#passed in from function instance_info and self
	{
		virt=$2
		echo ""
		echo "Virtaul Machine status on client"
		echo "*******************************"
		ssh -i ./rsa_keys/$1 $1 virsh list | grep -i $virt
		echo "*******************************"
		echo ""
		if [ $? -ne "0" ]
			then 
				echo "*******************************"
				echo "Virtual Machine was destroyed on physical compute node, continue forward:"
				echo "*******************************"
			else
				echo "Virtual Machine is still running on physical compute node, you need to stop it."
				echo "enter one of the following"
				echo "*******************************"
				echo "(1) kill instance on physicall server (when all else fails)"
				echo "(2) try to kill again with nova (suggested)"
				echo "*******************************"
				read kill_choice
				if [ $kill_choice == "1" ]; then 
					echo "Running the command \"virsh destroy $virt\" on server: $1" 
				elif [ $kill_choice == "2" ]; then
					echo "$4"
					exit
					echo "Running the commands \"source /home/crowbar/operationsrc ; nova delete $4\""
					echo "hit cntr+c in the next 5 seconds if this is wrong"
					sleep 5
					source /home/crowbar/operationsrc 
					nova delete $4
					echo "please allow 1 minute for the delete to work properly"
				fi
				get_virsh_info $1 $2 $3 $4
		fi
	}


instance_info ()
	{
	
	instance_query=`mysql --password=$password -u nova -h 172.23.196.82  nova  -e "select  power_state,  uuid, instances.hostname, CONCAT('instance-000000', HEX(instances.id)) as virsh_id ,instances.host, address  from fixed_ips, instances where fixed_ips.virtual_interface_id > 1 and instances.uuid = '$1' limit 1 " | grep $1 `

	power_state=`echo $instance_query | awk '{print $1}'`
	instance_id=`echo $instance_query | awk '{print $2}'`
	vm_name=`echo $instance_query | awk '{print $3}'`
	local_name=`echo $instance_query | awk '{print $4}'`
	server_hosting=`echo $instance_query | awk '{print $5}'`
	virt_ip=`echo $instance_query | awk '{print $6}'`
	
	
	if [ ! "$2" ]
		then	
			echo "If this is the correct virtual instance you would like to destroy: (y)"
			read answer
			if [ $answer == "y" ];
				then 
					get_virsh_info $server_hosting $local_name $instance_id $vm_name
					clean_mysql $instance_id
				else
					clean_failed_instance
			fi
	elif [ "$2" == "vnc" ]
		then
				echo "$server_hosting $local_name"
	else

		echo "******************************************"
		echo "Virtual machine info:"
		echo "******************************************"
		echo "Vm Name:"
		echo "	$vm_name"	
		echo "Vm local ip:"
		echo "	$virt_ip"	
		echo "Server hosting vm:"
		echo "	$server_hosting"	
		echo "Vm name on Server:"
		echo "	$local_name"	
		echo "Instance Id:"
		echo "	$instance_id"	
		echo "******************************************"
			
	fi
	}


search_vm_id ()
	{

	for i in `list_uuid_to_host`; 
		do 
			if [ $1 = $i ]; 
				then id_confirmed=$i; 
			fi ; 
		done 
	if [ $id_confirmed ]
		then
			instance_info $id_confirmed
		else 
			echo "please provide a valid server id"
	fi
		

	}


instance_id_request ()
	{
		echo " "
		echo " "
		echo " "
		echo "********************************************************************************************************* "
		echo "Please provide and instance id to clean from the following list:"
		echo "NOTE this will wipe any and all exsistance of this instance, if you get the wrong ID we will have problems."
		echo "********************************************************************************************************* "
		echo " "
		sleep 3
	
	}

clean_failed_instance ()
	{
		#instance_id_request
		if [ "$1" ]; then 
			search_vm_id $1
			
		else 
			echo "********************************************************************************************************* "
			echo "please rerun the command with 2nd argument as vm id"
			echo "********************************************************************************************************* "
			list_uuid_to_host
		fi

	}

create_instance_vnc_forward_syntax ()
	{
		server=`instance_info $1 "vnc" | awk '{print $1}' `
		instance=`instance_info $1 "vnc" | awk '{print $2}' `
		public_ip=`ifconfig  | grep 134.12 | awk -F ":" '{print $2}'  | awk '{print $1}'`
		vncinfo=`ssh -i ./rsa_keys/$server $server "virsh vncdisplay $instance"` 
		ip=`echo  $vncinfo | awk -F ":" '{print $1}'`
		port=`echo  $vncinfo | awk -F ":" '{print $2}'`

		echo "Ssh command to forward to vnc port:"
		echo "**********************************************"
		echo "ssh -L 590$port:$ip:590$port crowbar@$public_ip"
		echo "**********************************************"
		echo ""
		echo "After running this command you can use a vnc_client and log into localhost port $port."
	}


list_open_virt_interfaces ()
	{
		mysql --password=$password -u nova -h 172.23.196.82  nova  -e "select task_state, power_state, vm_state, user_id, uuid, instances.hostname, CONCAT('instance-000000', HEX(instances.id)) as virsh_id ,instances.host, address  from fixed_ips, instances where fixed_ips.virtual_interface_id > 1 and fixed_ips.instance_id = instances.id  order by host"
	}

list_uuid_to_host ()
	{
		mysql --password=$password -u nova -h 172.23.196.82  nova  -e "select  instances.uuid, instances.hostname from fixed_ips, instances where fixed_ips.virtual_interface_id > 1 and fixed_ips.instance_id = instances.id "
	}


case "$1" in 

--list_open_virt_interfaces) 
	list_open_virt_interfaces
	;;

--list_uuid_to_host)
	list_uuid_to_host
	;;

--clean_failed_instance)
	clean_failed_instance $arg1 
	;;

--create_instance_vnc_forward_syntax)
	if [ "$arg1" ];
		then 
			create_instance_vnc_forward_syntax $arg1 "vnc" 
	else
		echo "please provide a vm id"
		list_uuid_to_host
	fi
	;;
				

--instance_info)
	if [ "$arg1" ];
		then 
			instance_info $arg1 "true"
	else
		echo "please provide a vm id"
		list_uuid_to_host
	fi
	;;	

*) 
        return_statement
        ;;
esac
