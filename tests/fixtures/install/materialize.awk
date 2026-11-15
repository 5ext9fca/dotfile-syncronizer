# Apply literal line edits to a fixture; never parse production configuration.
BEGIN { FS="\t" }
NR==FNR {
  if(/^#/) next
  if(NF!=4 || $2 !~ /^[0-9]+$/ || $2<1) {bad=1;exit 1}
  if($1=="delete") {if($2 in deleted) {bad=1;exit 1};deleted[$2]=$3}
  else if($1=="insert") prefix[$2]=prefix[$2] $4 "\n"
  else {bad=1;exit 1}
  if($2>last) last=$2
  next
}
{
  if(FNR in prefix) printf "%s",prefix[FNR]
  if(FNR in deleted) {if($0!=deleted[FNR]) {bad=1;exit 1}}
  else print
  lines=FNR
}
END {
  if(bad || last>lines+1 || ((lines+1) in deleted)) exit 1
  if((lines+1) in prefix) printf "%s",prefix[lines+1]
}
