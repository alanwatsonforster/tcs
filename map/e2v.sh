paste $1 $2 | 
awk '
BEGIN { 
  print "("; 
} 
END { 
  print ")"; 
} 
NF == 28 { 
  print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $25, $26, $27, $14; 
}'
