#!/bin/bash
#
# This script will monitor another NAT instance and take over its routes
# if communication with the other instance fails
#
if [ -z $1 ]; then
    echo "Usage: $0 <ZONE> -- e.g. $0 AZ1"
    exit 1
fi

# Set friendly names for the arguments 
resource="nat.${1,,}"

# Delete cached files for GCR
rm -rf /tmp/gcr

# Get various values from GCR
partner_instance=`/usr/local/bin/get_gcr_val $resource partner_instance`
partner_publicrt=`/usr/local/bin/get_gcr_val $resource partner_publicrt`
partner_privatert=`/usr/local/bin/get_gcr_val $resource partner_privatert`
my_publicrt=`/usr/local/bin/get_gcr_val $resource my_publicrt`
my_privatert=`/usr/local/bin/get_gcr_val $resource my_privatert`
region=`/usr/local/bin/get_gcr_val region region`

# NAT instance variables
# Other instance's IP to ping and route to grab if other node goes down
NAT_ID=${partner_instance}
NAT_RT_ID1=${partner_publicrt}
NAT_RT_ID2=${partner_privatert}

# My route to grab when I come back up
My_RT_ID1=${my_publicrt}
My_RT_ID2=${my_privatert}

# Specify the EC2 region that this will be running in (e.g. https://ec2.us-east-1.amazonaws.com)
EC2_URL=https://ec2.${region}.amazonaws.com

# Health Check variables
Num_Pings=8
Ping_Timeout=2
Wait_Between_Pings=5
Wait_for_Instance_Stop=60
Wait_for_Instance_Start=300

# Run aws-apitools-common.sh to set up default environment variables and to
# leverage AWS security credentials provided by EC2 roles
. /etc/profile.d/aws-apitools-common.sh

# Determine the NAT instance private IP so we can ping the other NAT instance, take over
# its route, and reboot it.  Requires EC2 DescribeInstances, ReplaceRoute, and Start/RebootInstances
# permissions.
#
# Get this instance's ID and partner IP address
Instance_ID=`/usr/bin/curl --silent http://169.254.169.254/latest/meta-data/instance-id`

echo `date` "-- Starting NAT monitor"

echo `date` "-- Adding this instance to $My_RT_ID1 and $My_RT_ID2 default route on start"

/opt/aws/bin/ec2-replace-route $My_RT_ID1 -r 0.0.0.0/0 -i $Instance_ID -U $EC2_URL
# If replace-route failed, then the route might not exist and may need to be created instead
if [ "$?" != "0" ]; then
    /opt/aws/bin/ec2-create-route $My_RT_ID1 -r 0.0.0.0/0 -i $Instance_ID -U $EC2_URL
fi

/opt/aws/bin/ec2-replace-route $My_RT_ID2 -r 0.0.0.0/0 -i $Instance_ID -U $EC2_URL
# If replace-route failed, then the route might not exist and may need to be created instead
if [ "$?" != "0" ]; then
    /opt/aws/bin/ec2-create-route $My_RT_ID2 -r 0.0.0.0/0 -i $Instance_ID -U $EC2_URL
fi

while [ . ]; do
    # Check health of other NAT instance
    #
    # Fetch IP
    NAT_IP=`/opt/aws/bin/ec2-describe-instances $NAT_ID -U $EC2_URL | grep PRIVATEIPADDRESS -m 1 | awk '{print $2;}'`

    if [ -z $NAT_IP ]; then
        echo `date` "No partner IP address found -- sleeping for 5 seconds before trying again..."
        sleep 5
        continue
    fi

    # Perform ping test
    pingresult=`ping -c $Num_Pings -W $Ping_Timeout $NAT_IP | grep time= | wc -l`
    # Check to see if any of the health checks succeeded, if not
    if [ "$pingresult" == "0" ]; then
        # Set HEALTHY variables to unhealthy (0)
        ROUTE_HEALTHY=0
        NAT_HEALTHY=0
        STOPPING_NAT=0
        while [ "$NAT_HEALTHY" == "0" ]; do
            # NAT instance is unhealthy, loop while we try to fix it
            if [ "$ROUTE_HEALTHY" == "0" ]; then
                echo `date` "-- Other NAT heartbeat failed, taking over $NAT_RT_ID1 and $NAT_RT_ID2 default route"
                /opt/aws/bin/ec2-replace-route $NAT_RT_ID1 -r 0.0.0.0/0 -i $Instance_ID -U $EC2_URL
                /opt/aws/bin/ec2-replace-route $NAT_RT_ID2 -r 0.0.0.0/0 -i $Instance_ID -U $EC2_URL
                ROUTE_HEALTHY=1
            fi
            # Check NAT state to see if we should stop it or start it again
            NAT_STATE=`/opt/aws/bin/ec2-describe-instances $NAT_ID -U $EC2_URL | grep INSTANCE | awk '{print $5;}'`
            if [ "$NAT_STATE" == "stopped" ]; then
                echo `date` "-- Other NAT instance stopped, starting it back up"
                /opt/aws/bin/ec2-start-instances $NAT_ID -U $EC2_URL
                NAT_HEALTHY=1
                sleep $Wait_for_Instance_Start
            else
                if [ "$STOPPING_NAT" == "0" ]; then
                    echo `date` "-- Other NAT instance $NAT_STATE, attempting to stop for reboot"
                    /opt/aws/bin/ec2-stop-instances $NAT_ID -U $EC2_URL
                    STOPPING_NAT=1
                fi
                sleep $Wait_for_Instance_Stop
            fi
        done
    else
        sleep $Wait_Between_Pings
    fi
done
