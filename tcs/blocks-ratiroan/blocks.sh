#!/bin/sh

################################################################################

dir=/usr/local/var/tcs/blocks

################################################################################

allblocks () {
  if test $# != 2
  then
    echo 1>&2 "usage: allblocks prefix priority"
    exit 1
  fi
  prefix=$1
  priority=$2
  for file in $prefix-*
  do
    echo cp $file $dir/$priority-$file
  done
}

singleblock () {
  if test $# != 2
  then
    echo 1>&2 "usage: singleblock file priority"
    exit 1
  fi
  file=$1
  priority=$2
  echo cp $file $dir/$priority-$file
}

################################################################################

sh focus.sh
sh pointing-map.sh
#sh sdss-standards.sh
#sh landolt-standard-fields.sh
#sh stripe-82.sh
#sh pointing-map.sh
#sh sky-brightness.sh
#sh 2017A-0010.sh

# sh go-fox.sh
# sh go-michel.sh
# sh 2018A-2000.sh

################################################################################

(
  echo mkdir -p $dir
  
  if test "$date" = "default"  
  then
    echo rm -rf $dir
  fi

  echo mkdir -p $dir

  if test "$date" != "default"  
  then
    
    :
     
    #allblocks 0008-pointing-map           w

  fi

  #for letter in a b c d e f g h i j k l m n o p q r s t u v w x y z
  #do 
  #  singleblock 2019B-1002-0 e$letter
  #done

  singleblock 2008-fox-0 c0
  singleblock 2008-fox-0 c1

  singleblock 2006-rosales-11 d0
  singleblock 2006-rosales-11 d1

  singleblock 2007-gonzalez-0 i0

  allblocks 0004-initial-focus          m
  allblocks 0004-focus                  n

  allblocks 0001-twilight-flats-bright  x
  allblocks 0001-twilight-flats-faint   x
  allblocks 0002-biases                 y
  allblocks 0003-dark                   z

) | sudo sh
