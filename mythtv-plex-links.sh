#!/bin/bash
# Original script written by Justin Decker, copyright 2015. For licensing
# purposes, use GPLv2
#
# To use, create a "user job" that runs like so:
#  /path/to/script/mythtv-plex-links.sh "%CHANID%" "%STARTTIMEUTC%"

function error_exit {
  echo "${1} : exiting"
  exit 1
}
#/usr/local/bin/mythtv-plex-links.sh "1092" "2016-08-24 03:30:00"
# The following values adjust the script parameters:
#
# Set this to the directory of the Plex Library where myth recording symlinks
# should reside.
PLEXLIBRARYDIR="/media/Storage2/recordings/Episodes"


PRIMARY_DIR="/media/Storage2/recordings"
SECONDARY_DIR="/var/lib/mythtv/recordings"

# Set this to the location of the mythtv config.xml file. It's needed to
# determine the mysql login. If you're running mythbuntu, you shouldn't need to
# change this.
# TODO: sanity check file and db values
CONFIGXML="/home/mythtv/.mythtv/config.xml"

#Backup directory to move original recording
BACKUP_DIR="/tmp/media_backup"

# Leave everything below this line alone unless you know what you're doing.
#
# Discover mysql username and password from mythtv config.xml. Alternatively
# you can manually enter them after the = sign.
DBUSER="$(awk -F '[<>]' '/UserName/{print $3}' $CONFIGXML)"
DBPASS="$(awk -F '[<>]' '/Password/{print $3}' $CONFIGXML)"

# TODO: sanity check values (sql injection)
CHANID=$1 && STARTTIME=$2

# Populate recording information from sql database. Set field separator (IFS)
# to tab and tell mysql to give us a tab-delimited result with no column names
# (-Bs). Without this, IFS defaults to any whitespace, meaning words separated
# by spaces in the result fields (such as the title) would be interpreted as
# individual array elements. That would be bad since we expect the whole
# title to be contained in array element 0 later.
OLDIFS=$IFS
IFS=$'\t'
RECORDING=($(mysql mythconverg --user=$DBUSER --password=$DBPASS -Bse \
  "SELECT title, season, episode, basename, subtitle  FROM recorded WHERE chanid=\"$CHANID\" AND starttime=\"$STARTTIME\" LIMIT 1;"))
IFS=$OLDIFS

# Set vars from above query results, padding season and episode with 0 if needed
# TODO: sanity check values
TITLE=${RECORDING[0]}
SEASON=`printf "%02d" ${RECORDING[1]}`
EPISODE=`printf "%02d" ${RECORDING[2]}`
FILENAME=${RECORDING[3]}
SUBTITLE=${RECORDING[4]}

# If season is '00', use 2 digit year
if [ "$SEASON" == "00" ]; then
  SEASON=`date +%y`
fi
# If episode is '00', use 3 digit day-of-year
if [ "$EPISODE" == "00" ]; then
  EPISODE=`date +%j`
fi

if [ -e "${PRIMARY_DIR}/${FILENAME}" ]
then
  MYTHFILE="$PRIMARY_DIR/$FILENAME"
else
  MYTHFILE="$SECONDARY_DIR/$FILENAME"
fi

PLEXFILE="$TITLE - S${SEASON}E${EPISODE} (${SUBTITLE}).mp4"
PLEXSHOWDIR="$PLEXLIBRARYDIR/$TITLE/Season ${SEASON}"
PLEXFILEPATH="$PLEXSHOWDIR/$PLEXFILE"

if [ ! -e "$MYTHFILE" ]; then
  error_exit "storage group directory did not pull from db correctly"
fi
# create plex library subdir and symlink for this recording
echo "Making directory ${PLEXSHOWDIR}"
mkdir -p "$PLEXSHOWDIR" || error_exit "Failed to make show directory"

# backup file before transcoding
echo "Making backup directory ${PLEXSHOWDIR}"
mkdir -p "$BACKUP_DIR" || error_exit "failed to make the backup directory"
cp "$MYTHFILE" "$BACKUP_DIR/$FILENAME" || error_exit "failed to copy the original file to the backup directory"

# transcode video to mp4
HandBrakeCLI -i "$MYTHFILE" -o "$PLEXFILEPATH" --preset="High Profile" || error_exit "failed during the handbrake transcode"

#remove original recording
rm "$MYTHFILE" || error_exit "failed to remove original file: ${MYTHFILE}"
#link transcoded veresion to original
ln -s "$PLEXFILEPATH" "$MYTHFILE" || error_exit "failed to link the newly transcoded file"

# Prune all dead links and empty folders
#find "$PLEXLIBRARYDIR" -xtype l -delete
#find "$PLEXLIBRARYDIR" -type d -empty -delete

exit 0