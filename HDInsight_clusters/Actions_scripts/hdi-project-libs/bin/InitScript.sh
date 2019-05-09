#!/bin/bash
rm -Rf /tmp/initscript/
mkdir /tmp/initscript/
#ARGs
whoami > /tmp/initscript/output_bash.log
echo $@ >> /tmp/initscript/output_bash.log

echo "Check des param">> /tmp/initscript/output_bash.log
echo $3 $5 $7 $8 >> /tmp/initscript/output_bash.log

#UtilitiesHDI
/usr/bin/curl https://hdiconfigactions.blob.core.windows.net/linuxconfigactionmodulev01/HDInsightUtilities-v01.sh -o /tmp/HDInsightUtilities-v01.sh
chmod +x /tmp/HDInsightUtilities-v01.sh
source /tmp/HDInsightUtilities-v01.sh

#Installation de Xsltproc
sudo apt-get install -y xsltproc

#Ajout de la timezone Paris
sudo cp -vf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo Europe/Paris | sudo tee /etc/timezone

#GETHEADNODE
HOSTNAME=$(hostname -f)
PRIMARYHEADNODE=`get_primary_headnode`

if [[ $HOSTNAME == $PRIMARYHEADNODE ]];then
    #Set env
    declare -x USER=$4
    declare -x HOME=/home/$4

    cd $HOME
    echo "######## Tous les pkgs ############" >> /tmp/initscript/output_bash.log
    pkgs=$(echo $6 | tr "?" "\n")
    echo $6 >> /tmp/initscript/output_bash.log

    for pkg in $pkgs
    do          
            echo "########### package #############" >> /tmp/initscript/output_bash.log
            package=$(echo $pkg | cut -d "|" -f 1) 
            echo $package>> /tmp/initscript/output_bash.log

            #Call archive
            echo "########## CURL package #############" >> /tmp/initscript/output_bash.log
            dlpkg=$(/usr/bin/curl "$1$package$2" -o $HOME/$package) 
            echo "/usr/bin/curl "$1$package$2" -o $HOME/$package" >> /tmp/initscript/output_bash.log
            if [ $? -ne 0 ]; then
                echo "ERROR: Le livrable $package n\'a pas pu être téléchargé" >> /tmp/initscript/output_bash.log
                exit 1
            fi

            checksum=$(echo $pkg |cut -d "|" -f 2 | cut -d "#" -f 1)

            #dezip
            unzip $HOME/$package -d $HOME
            if [ $? -ne 0 ]; then
                echo "ERROR: Le livrable $i n\'a pas pu être décompressé" >> /tmp/initscript/output_bash.log
                exit 1
            fi

            initscript=$(echo $pkg |cut -d "|" -f 2 | cut -d "#" -f 2 | cut -d "/" -f 1)
            arginitscript=$(echo $pkg |cut -d "|" -f 2 | cut -d "#" -f 2 | cut -d "/" -f 2 | sed s/"@"//g | sed s/";"/" "/g)
            if [ "$initscript" == "initnull" ]
            then
                    echo "RAF";
            elif [ "$arginitscript" == "argnull" ]
            then
                    chown -R $USER:$USER $HOME/*
                    sudo -u $USER chmod +x $HOME/$initscript 
                    sudo -u $USER $HOME/$initscript $3 $5 $7 $8
            else
                    #Call script
                    chown -R $USER:$USER $HOME/*
                    sudo -u $USER chmod +x $HOME/$initscript 
                    sudo -u $USER $HOME/$initscript $3 $5 $7 $8 $arginitscript
            fi
    done
fi

exit 0