#!/bin/sh
# Written by Filipe Laborde, fil@rezox.com 
# Version 0.5
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
read -e -r -p "How many video files to merge? (1) " total_files
if [ -z $total_files ]; then
  total_files=1;
fi

cmd_cnt=0
file_idx=1
output_resolution=""
output_fps=""
output_vbps="2.5"
while [ $file_idx -le $total_files ]; do
   echo "............................................."

   read -e -r -p "Enter video file #${file_idx}: " filename
   file_ext=`echo "${filename##*.}" | tr '[:upper:]' '[:lower:]'`
   video_info=`ffprobe -v error -select_streams v:0 -show_entries stream=width,height,codec_name,avg_frame_rate -of csv=s=x:p=0 ${filename}`
   video_info=(${video_info//x/ })
   video_codec="${video_info[0]}"
   resolution="${video_info[1]}x${video_info[2]}"
   fps=`printf %.2f $(echo "${video_info[3]}+0.0001" | bc -l)`
   duration_time=`ffprobe ${filename} 2>&1 | grep -E '^ +Duration' | cut -d':' -f2- | cut -d, -f1- | cut -d'.' -f1`
   if [ -z $duration_time ]; then
      echo "ERROR: Sorry ${filename} an invalid video file. Quitting."
      exit
   fi;

   echo "   * Detected: ${resolution}, ${fps} fps, ${video_codec}/${file_ext}, duration: ${duration_time}"
   # only ask on first file
   if [ "${file_idx}" -eq 1 ]; then
      prompt_vbps=0

      read -e -r -p "   - Resize output file? (currently ${resolution}): " output_resolution
      if [ "${#output_resolution}" -eq 0 ]; then
         output_resolution="${resolution}"      
      elif [ "${#output_resolution}" -gt 5 ]; then
         prompt_change_vbps=1
         echo "   -- Ok adjusting all clips to ${output_resolution}"
      else
         echo "ERROR: Invalid resizing resolution (${output_resolution}): ex. 1920x1080, 1280x720, 640x480, ..."
         exit
      fi

      read -e -r -p "   - Change frame-rate? (currently ${fps}): " output_fps
      if [ "${#output_fps}" -eq 0 ]; then
         output_fps="${fps}"      
      elif [ "$output_fps" -ge 1 ] && [ "$output_fps" -le 300 ]; then
         prompt_change_vbps=1
         echo "   -- Ok adjusting all clips to ${output_fps} fps"
      else
         echo "ERROR: Invalid frame-per-second (${new_fps}): use for example: 5, 10, 24, 30, 60, 120"
         exit
      fi

      # only bother prompting for the video-bits-per-second if one of the above changed
      if [ "$prompt_change_vbps" ]; then
         read -e -r -p "   - Change encode-quality? (currently 3M, enter 1-3): " output_vbps
         if [ "${#output_vbps}" -eq 0 ]; then
            output_vbps="2.5"
         elif [ "$output_vbps" -ge 1 ] && [ "$output_vbps" -le 4 ]; then
            echo "   -- Ok adjusting all clips to ${output_vbps}M bit-rate"
         else
            echo "ERROR: Invalid video bit-rate (${output_vbps}): use 1.0 (for smallest file), 2 (for decent size/quality), 3.0 (for highest quality)"
            exit
         fi
      fi
   fi

   read -e -r -p "   - start time (default 00:00:00): " file_start_time
   if [ ! "${#file_start_time}" -eq 0 ] && [ ! "${#file_start_time}" -eq 8 ]; then
      echo "ERROR: Invalid start-time (${file_start_time}) not in HH:MM:SS format."
      exit
   fi

   read -e -r -p "   - end time (default video-end: ${duration_time}): " file_end_time
   if [ ! "${#file_end_time}" -eq 0 ] && [ ! "${#file_end_time}" -eq 8 ]; then
      echo "ERROR: Invalid end-time (${file_end_time}) not in HH:MM:SS format."
      exit
   fi

   # build temp file using extracted portion of video (or codec change)
   if [ "${#file_start_time}" -eq 0 ] && [ "${#file_end_time}" -eq 0 ] && [ $file_ext = "mp4" ] && [ $video_codec = "h264" ] && [ $output_resolution = $resolution ]; then
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

      if [ $file_ext = "mp4" ] && [ $video_codec = "h264" ] && [ $output_resolution = $resolution ] && [ $output_fps = $fps ]; then
         cmd+="-c copy "
      elif [ ! $output_resolution = $resolution ] || [ ! $output_fps = $fps ]; then
         # if resampling, make it smaller (3M bit-rate hardcoded, index@start)
         cmd+="-s ${output_resolution} -r ${output_fps} -c:v libx264 -b:v ${output_vbps}M -strict -2 -movflags faststart "
      elif [ $video_codec = "h264" ]; then
         # since size good & codec good, keep video codec.
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
