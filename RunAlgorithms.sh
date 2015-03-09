#!/bin/bash
#
# Call CDPro executables, somewhat more nicely.
#
# Before calling this script, convert CD spec output file to Delta epsilon with:
#
#	``CDToGnuplot -r <# residues> -m <MW (Da)> -c <conc. (mg/ml)> [-b <buffer file>] <InFile   >OutFile''
#
# Calls ``GenerateCDProInput'' to make the CDPro input file (this would ordinarily have been done by CRDATA.EXE)
#
# CDPRO_DIR must be set to the location of the CDPro executables.
#    -- At some point i should change this to look in $PATH.
#
# Requires perl, gnuplot, wine, CDPro
#

CDPRO_DIR="/home/sgordon/Downloads/CDPro"

#Set this if you get ``run-detectors: unable to find an interpreter for Continll.exe'' etc
#WINE=""
WINE="wine"

# Output filename case:
# I've had systems that produced either uppercase, or lowercase.
# possibly depending on whether the install was under ~/.wine (ext3/4)
OUTPUT_CASE=upper

if [ "$OUTPUT_CASE" = "upper" ]
then
    CONTINLL_OUT="CONTINLL.OUT"
    SELCON3_OUT="SELCON3.OUT"
    CDSSTR_OUT="CDsstr.out"
elif [ "$OUTPUT_CASE" = "lower" ]
then
    CONTINLL_OUT="continll.out"
    SELCON3_OUT="selcon3.out"
    CDSSTR_OUT="cdsstr.out"
else
    echo "$0: I don't understand OUTPUT_CASE='$OUTPUT_CASE'"
fi

if [ "$#" == "0" ]
then
    echo "Usage: $0 <CDSpec-data-files>"
fi


SCRIPT_DIR=`dirname $0`/





for DataFile in "$@"
do
  DataDir=`basename "${DataFile}"`-CDPro
  mkdir -p "$DataDir"
  echo Processing ${DataFile} into $DataDir:


  #    echo ${SCRIPT_DIR}GenerateCDProInput
  #    echo "${SCRIPT_DIR}GenerateCDProInput < "${DataFile}" >| input"
  ${SCRIPT_DIR}GenerateCDProInput < "${DataFile}" >| input
  #    cat input

  cp input "$CDPRO_DIR/"
  cd "$CDPRO_DIR/"

  for i in {1..10};  # (ibasese)
  do
    echo -n "ibasis $i ";
    perl -pni -e 's/^(\s+\d\s+)\d+(

    echo -n "continll"
    echo | $WINE Continll.exe > stdout || echo -n " (crashed)"
    #	echo
    #	ls
    #	echo
    mkdir -p "$OLDPWD/$DataDir/continll-ibasis$i"
    mv CONTIN.CD CONTIN.OUT $CONTINLL_OUT BASIS.PG ProtSS.out SUMMARY.PG stdout "$OLDPWD/$DataDir/continll-ibasis$i"
    cp input "$OLDPWD/$DataDir/continll-ibasis$i"

    echo -n ", selcon3"
    echo | $WINE SELCON3.EXE > stdout
    #	echo
    #	ls
    #	echo
    mkdir -p "$OLDPWD/$DataDir/selcon3-ibasis$i"
    if grep -q 'Program CRASHED -- No SOLUTIONS were Obtained' $SELCON3_OUT
    then
      echo -n " (crashed)";
    else
      mv ProtSS.out "$OLDPWD/$DataDir/selcon3-ibasis$i"
    fi
    mv CalcCD.OUT $SELCON3_OUT stdout "$OLDPWD/$DataDir/selcon3-ibasis$i"
    cp input "$OLDPWD/$DataDir/selcon3-ibasis$i"

    echo -n , cdsstr
    echo | $WINE CDSSTR.EXE > stdout || echo -n " (crashed)";
    #	echo
    #	ls
    #	echo
    mkdir -p "$OLDPWD/$DataDir/cdsstr-ibasis$i"
    mv reconCD.out ProtSS.out $CDSSTR_OUT stdout "$OLDPWD/$DataDir/cdsstr-ibasis$i"
    cp input "$OLDPWD/$DataDir/cdsstr-ibasis$i"
    echo .
  done

  cd "$OLDPWD"


  cd "$DataDir/"

  #
  # What are the best fits ?
  #
  # This works ok, but doesn't try to resolve situations
  # where multiple ibasese have the same RMSD.
  #
  plotlines=""
  for i in continll selcon3 cdsstr
  do
    BEST_RMSD_LINE=`/bin/grep -hw RMSD $i-ibasis*/ProtSS.out | sort | head -n1`
    BEST_RMSD=`echo ${BEST_RMSD_LINE##*RMSD(Exp-Calc): }`
    BEST_RMSD=${BEST_RMSD%%?}

    ibasis_filename=`grep -l  "$BEST_RMSD" $i-ibasis*/ProtSS.out|tail -n1` # only return  one
    echo $ibasis_dirname
    ibasis_dirname=`dirname ${ibasis_filename}`
    ibasis=${ibasis_dirname##*-ibasis}

    echo "Best $i is RMSD: ${BEST_RMSD} (ibasis $ibasis)"
    grep -B1 ^Frac "$ibasis_dirname/stdout"
    grep -l  "$BEST_RMSD" $i-ibasis*/ProtSS.out

    if [ "$i" = "continll" ]
    then
      echo $ibasis > best-continll
      # ln -sf continll-ibasis$ibasis best-continll
      ContinllPlot=", '$ibasis_dirname/CONTIN.CD' index 0 using 1:3 with lines smooth csplines title \"$i ibasis $ibasis: RMSD=${BEST_RMSD}\""
    elif [ "$i" = "selcon3" ]
    then
      # ln -sf selcon3-ibasis$ibasis best-selcon3
      echo $ibasis > best-selcon3
      Selcon3Plot=", '$ibasis_dirname/CalcCD.OUT' index 0 using 1:3 with lines smooth csplines title \"$i ibasis $ibasis: RMSD=${BEST_RMSD}\""
    elif  [ "$i" = "cdsstr" ]
    then
      #ln -sf cdsstr-ibasis$ibasis best-cdsstr
      echo $ibasis > best-cdsstr
      CdsstrPlot=", '$ibasis_dirname/reconCD.out' index 0 using 1:4 with lines smooth csplines title \"$i ibasis $ibasis: RMSD=${BEST_RMSD}\""
    fi
  done


  #Print the gnuplot file:
  cat <<GPI > "bestFits.gpi"
  Assay="CDSpec-$DataFile-`date +"%Y%m%d"`-Overlay"
  DataFile="../$DataFile"
  OutputType='.pdf'

  set terminal pdfcairo enhanced color font 'Arial,12'
  set key samplen 2 spacing 0.75
  set grid xtics ytics mxtics mytics lt -1 lw 0.125 lc rgb "#eeeeee"

  set ylabel "{/Symbol D}{/Symbol e} (M^{-1}{/Symbol \\327} cm^{-1})"
  set xlabel "Wavelength (nm)"
  set mxtics 5
  set mytics 10
  set key top left
  # set yrange [-3:1]

  set tics nomirror
  set border 3 # Remove top and right axes. Bottom: 1, Left: 2, Top: 4, Right: 8

  set title "CD Spec ($DataFile): Absorbance Vs Wavelength"
  set output Assay.OutputType


  plot DataFile index 0 using 1:2 w p pt 7 ps 0.4 lc rgb "black" title "" $ContinllPlot $Selcon3Plot $CdsstrPlot

  GPI

  gnuplot bestFits.gpi



  #Print the best-continll file:
  cat <<GPI > "bestContinllFit.gpi"
  Assay="CDSpec-$DataFile-`date +"%Y%m%d"`-bestContinll"
  DataFile="../$DataFile"
  OutputType='.pdf'

  set terminal pdfcairo enhanced color font 'Arial,12'
  set key samplen 2 spacing 0.75
  set grid xtics ytics mxtics  mytics lt -1 lw 0.125 lc rgb "#eeeeee"

  set ylabel "{/Symbol D}{/Symbol e} (M^{-1}{/Symbol \\327} cm^{-1})"
  set xlabel "Wavelength (nm)"
  set mxtics 5
  set mytics 10
  set key top left
  # set yrange [-3:1]

  set tics nomirror
  set border 3 # Remove top and right axes. Bottom: 1, Left: 2, Top: 4, Right: 8

  set title "CD Spec ($DataFile): Absorbance Vs Wavelength"
  set output Assay.OutputType


  plot DataFile index 0 using 1:2 title ""  $ContinllPlot
  GPI

  gnuplot bestContinllFit.gpi


  #Print the best-Selcon3 file:
  cat <<GPI > "bestSelcon3Fit.gpi"
  Assay="CDSpec-$DataFile-`date +"%Y%m%d"`-bestSelcon3"
  DataFile="../$DataFile"
  OutputType='.pdf'

  set terminal pdfcairo enhanced color font 'Arial,12'
  set key samplen 2 spacing 0.75
  set grid xtics ytics mxtics  mytics lt -1 lw 0.125 lc rgb "#eeeeee"

  set ylabel "{/Symbol D}{/Symbol e} (M^{-1}{/Symbol \\327} cm^{-1})"
  set xlabel "Wavelength (nm)"
  set mxtics 5
  set mytics 10
  set key top left
  # set yrange [-3:1]

  set tics nomirror
  set border 3 # Remove top and right axes. Bottom: 1, Left: 2, Top: 4, Right: 8

  set title "CD Spec ($DataFile): Absorbance Vs Wavelength"
  set output Assay.OutputType


  plot DataFile index 0 using 1:2 title ""  $Selcon3Plot
  GPI

  gnuplot bestSelcon3Fit.gpi


  #Print the best-CdsstrPlot file:
  cat <<GPI > "bestCdsstrPlotFit.gpi"
  Assay="CDSpec-$DataFile-`date +"%Y%m%d"`-bestCdsstrPlot"
  DataFile="../$DataFile"
  OutputType='.pdf'

  set terminal pdfcairo enhanced color font 'Arial,12'
  set key samplen 2 spacing 0.75
  set grid xtics ytics mxtics  mytics lt -1 lw 0.125 lc rgb "#eeeeee"

  set ylabel "{/Symbol D}{/Symbol e} (M^{-1}{/Symbol \\327} cm^{-1})"
  set xlabel "Wavelength (nm)"
  set mxtics 5
  set mytics 10
  set key top left
  # set yrange [-3:1]

  set tics nomirror
  set border 3 # Remove top and right axes. Bottom: 1, Left: 2, Top: 4, Right: 8

  set title "CD Spec ($DataFile): Absorbance Vs Wavelength"
  set output Assay.OutputType


  plot DataFile index 0 using 1:2 title ""  $CdsstrPlot
  GPI

  gnuplot bestCdsstrPlotFit.gpi

  cd ..

done