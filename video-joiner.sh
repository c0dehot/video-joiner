#!/bin/sh
# Written by Filipe Laborde, fil@rezox.com 
# Date: March, 2020
# License: MIT
# Use as you wish, all risk is yours.
# Compatible with unix based systems (Mac, Ubuntu, Debian, etc.)
#
# Usage: ./video-joiner.sh [output.mp4] [src-dir]
# It will prompt for the files to append together

file_out=$1
if [ "${#1}" -eq 0 ]; then
   echo "ERROR: Please give the output filename, ex. ./video-joiner.sh output.mp4"
   exit
fi

# init
starttime=`date +%s`
ffmpeg_file_list="ffmpeg_list.txt"
rm -f $ffmpeg_file_list
touch $ffmpeg_file_list

## check for dependencies - check expected paths ##
dep_path=("/usr/local/bin/" "/usr/local/opt/" "/usr/bin/" "/usr/share/")
has_ffmpeg=0
has_ffprobe=0
for dep in ${dep_path[*]}; do
   if [ -x "${dep}ffmpeg" ]; then has_ffmpeg=1; fi
   if [ -x "${dep}ffprobe" ]; then has_ffprobe=1; fi
done

if [ $has_ffmpeg -eq 0 ] || [ $has_ffprobe -eq 0 ] ; then
   echo "ERROR: Missing 'ffmpeg'/'ffprobe', please install, ex. (linux) apt install ffmpeg, (mac) brew install ffmpeg"
   exit
fi;

## loop through videos to join ##
read -e -r -p "Join how many video files? (1) " total_files
if [ -z $total_files ]; then
  total_files=1;
fi

cmd_cnt=0
file_idx=1
while [ $file_idx -le $total_files ]; do
   echo "............................................."

   read -e -r -p "$file_idx: Enter the video file: " filename
   file_ext=`echo "${filename##*.}" | tr '[:upper:]' '[:lower:]'`
   video_info=`ffprobe -v error -select_streams v:0 -show_entries stream=width,height,codec_name -of csv=s=x:p=0 ${filename}`
   video_info=(${video_info//x/ })
   video_codec="${video_info[0]}"
   resolution="${video_info[1]}x${video_info[2]}"
   duration_time=`ffprobe ${filename} 2>&1 | grep -E '^ +Duration' | cut -d':' -f2- | cut -d, -f1- | cut -d'.' -f1`
   if [ -z $duration_time ]; then
      echo "ERROR: Sorry ${filename} an invalid video file. Quitting."
      exit
   fi;

   read -e -r -p "   .. info: ${resolution}, ${file_ext}, duration: ${duration_time} -- start at (default 00:00:00): " file_start_time
   if [ ! "${#file_start_time}" -eq 0 ] && [ ! "${#file_start_time}" -eq 8 ]; then
      echo "ERROR: Invalid start-time (${file_start_time}) not in HH:MM:SS format."
      exit
   fi

   read -e -r -p "   .. ok, and truncate video at? (default ${duration_time} [ie end]): " file_end_time
   if [ ! "${#file_end_time}" -eq 0 ] && [ ! "${#file_end_time}" -eq 8 ]; then
      echo "ERROR: Invalid end-time (${file_end_time}) not in HH:MM:SS format."
      exit
   fi

   # build temp file using extracted portion of video (or codec change)
   if [ "${#file_start_time}" -eq 0 ] && [ "${#file_end_time}" -eq 0 ] && [ $file_ext = "mp4" ] && [ $video_codec = "h264" ]; then
      echo "file ${filename}" >> $ffmpeg_file_list
   else
      cmd="ffmpeg -hide_banner -loglevel panic -stats "
      if [ "${#file_start_time}" -eq 8 ]; then
         cmd+="-ss ${file_start_time} "
      fi
      cmd+="-i ${filename} "
      if [ "${#file_end_time}" -eq 8 ]; then
         cmd+="-to ${file_end_time} "
      fi

      if [ $file_ext = "mp4" ] && [ $video_codec = "h264" ]; then
         cmd+="-c copy "
      elif [ $video_codec = "h264" ]; then
         # since it's mkv or another container, but valid
         # mp4 code, let's KEEP the codec.
         cmd+="-vcodec copy "
      fi   
      tmp_filename=$filename`date +"%s"`".tmp.mp4"
      cmd+="${tmp_filename}"

      cmd_list[cmd_cnt]="${cmd}"
      ((cmd_cnt++))
      tmp_file_set+=($tmp_filename)
      echo "file ${tmp_filename}" >> $ffmpeg_file_list
   fi
   ((file_idx++))
done

# final operation is a join
cmd_list[cmd_cnt]="ffmpeg -hide_banner -loglevel panic -stats -f concat -i $ffmpeg_file_list -c copy ${file_out}"

# now do any individual video modifications and join
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo "Preparing video operations (have patience...)"
for cmd in "${cmd_list[@]}"
do
    $cmd
done

# deleting temp files
for file in ${tmp_file_set[*]}
do
    rm $file
done
rm -f $ffmpeg_file_list

endtime=`date +%s`
runtime=$((endtime-starttime))
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo "COMPLETE! Written ${file_out} in ${runtime} s"
echo "+++++++++++++++++++++++++++++++++++++++++++++"
echo 
