#!/bin/bash
set -x
echo "*** Phase 2 - SAS Mid-Tier Install Script Started at `date +'%Y-%m-%d_%H-%M-%S'` ***"

## Function for error handling
fail_if_error() {
  [ $1 != 0 ] && {
    echo $2
    exit 10
  }
}

##Global Variables
depot_loc=`facter sasdepot_folder` 
store_name=`facter storage_account_name`
store_loc=`facter file_share_name`   
app_name=`facter application_name`  
stgacc_secr_name=`facter stgacc_secr_name`
sas_role=`facter sas_role`   
domain_name=`facter domain_name`  
depot_loc=`facter sasdepot_folder` 
sas_sid=`facter sas_sid` 
host_name="${app_name}${sas_role}"
meta_host=`facter meta_hostname`
compute_host=`facter compute_hostname`
mid_host=`facter mid_hostname`
sasint_secret_name=`facter sasint_secret_name`
sasext_secret_name=`facter sasext_secret_name`
key_vault_name=`facter key_vault_name`
pub_keyname=`facter pub_keyname`
artifact_loc=`facter artifact_loc`
res_dir="/opt/sas/resources/responsefiles"
plan_file_url="${artifact_loc}properties/plan.xml"
midinstall_url="${artifact_loc}properties/mid_install.properties"
midconfig_url="${artifact_loc}properties/mid_config.properties"
inst_prop=${res_dir}/mid_install.properties
conf_prop=${res_dir}/mid_config.properties


# Getting the password
az login --identity
fail_if_error $? "ERROR: AZ Login Failed "
sasintpw=`az keyvault secret show -n $sasint_secret_name --vault-name $key_vault_name | grep value | cut -d '"' -f4`
sasextpw=`az keyvault secret show -n $sasext_secret_name --vault-name $key_vault_name | grep value | cut -d '"' -f4`
store_key=`az keyvault secret show -n $stgacc_secr_name --vault-name $key_vault_name | grep value | cut -d '"' -f4`   
echo `az keyvault secret show -n ${pub_keyname}  --vault-name ${key_vault_name} | grep value | cut -d '"' -f4` >> ~/.ssh/authorized_keys

#SAS group creation
cat /etc/group |grep -w sas
if [ $? -eq 0 ]; then
    echo "SAS Group exists"
else
    groupadd -g 5001 sas
    fail_if_error $? "ERROR: SAS group creation failed"
fi

##Creating SAS internal Users
username=("sasinst" "sassrv" "sasdemo")
userid=("1002" "1003" "1005")
for ((i=0;i<${#username[@]};++i));
do
    if [ ! -f /home/${username[$i]} ]; then
        useradd -u ${userid[$i]} -g sas ${username[$i]}
        fail_if_error $? "ERROR: failed to create ${username[$i]} User"
        echo ${sasextpw} | passwd ${username[$i]} --stdin
    else 
        echo "User ${username[$i]} exists"
    fi
done

##Set permissions for opt-sas and sasdepot directories
if [ ! -d /opt/sas/home ]; then 
    mkdir -p /opt/sas/resources /opt/sas/home /opt/sas/config
    fail_if_error $? "ERROR: SAS directories creation failed"
fi
chmod 775 /opt/sas -R
chown -R sasinst:sas /opt/sas
echo "Permissions for opt-sas and sasdepot have been set."

##Mount Azure File Share for SASDepot
df -h | grep -w /sasdepot
if [ $? -eq 0 ]; then
    echo "SASDepot already mounted."
else
    if [ ! -d "/etc/smbcredentials" ]; then
        sudo mkdir /etc/smbcredentials
    fi
    if [ ! -f "/etc/smbcredentials/store.cred" ]; then
        echo "username=${store_name}" >> /etc/smbcredentials/store.cred
        echo "password=${store_key}" >> /etc/smbcredentials/store.cred
    fi
    sudo chmod 600 /etc/smbcredentials/store.cred
    #echo "//${store_name}.file.core.windows.net/${store_loc} /sasdepot cifs nofail,vers=3.0,credentials=/etc/smbcredentials/store.cred,dir_mode=0777,file_mode=0777,serverino" >> /etc/fstab
    sudo mount -t cifs //${store_name}.file.core.windows.net/${store_loc} /sasdepot -o vers=3.0,credentials=/etc/smbcredentials/store.cred,dir_mode=0777,file_mode=0777,serverino
    fail_if_error $? "ERROR: Failed to Mount Azure file share"
fi

#copyign SID file to local directories from SASDepot
cp -rv /sasdepot/${depot_loc}/sid_files/${sas_sid} /opt/sas/resources/
if [ ! -d $res_dir ]; then
    mkdir -p $res_dir
fi
wget -P /opt/sas/resources/ $plan_file_url
wget -P $res_dir $midinstall_url
wget -P $res_dir $midconfig_url

#Changing the settings in property files
sed -i "s/domain_name/${domain_name}/g" $res_dir/*.properties
sed -i "s/host_name/${mid_host}/g" $res_dir/*.properties
sed -i "s/meta_host/${meta_host}/g" $res_dir/*.properties
sed -i "s|sas_plan_file_path|/opt/sas/resources/plan.xml|g" $res_dir/*.properties
sed -i "s|sas_license_file_path|/opt/sas/resources/${sas_sid}|g" $res_dir/*.properties

#SAS Installation
if [ -d /opt/sas/temp ]; then 
    chown sasinst /opt/sas/temp
else
    mkdir -p /opt/sas/temp
    chown sasinst /opt/sas/temp
fi

if [ -f ${inst_prop} ]; then
    if [ ! -f /opt/sas/home/SASFoundation/9.4/utilities/bin/setuid.sh ]; then
        su - sasinst -c "time /sasdepot/${depot_loc}/setup.sh -deploy -responsefile ${inst_prop} -lang en -loglevel 2 -templocation /opt/sas/temp -quiet"
        if [ $? -eq 0 ]; then
            echo "SAS Mid-Tier Server installation has been completed succesfully."
            sudo /opt/sas/home/SASFoundation/9.4/utilities/bin/setuid.sh
            echo "Setuid script has been run successfully."
        else
            echo "ERROR: SAS Mid-Tier Server installation has failed. Please check logs"
            exit 1
        fi
    else 
        echo "SAS Installation Completed. Proceeding to Configuration stage."
    fi
else
    echo "SAS Install Properties file not found. Exiting Now."
    exit 1
fi

echo "*** Phase 2 - SAS Mid-Tier Install Script Ended at `date +'%Y-%m-%d_%H-%M-%S'` ***"
