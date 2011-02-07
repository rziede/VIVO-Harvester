#!/bin/bash

# Copyright (c) 2010 Christopher Haines, Dale Scheppler, Nicholas Skaggs, Stephen V. Williams.
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the new BSD license
# which accompanies this distribution, and is available at
# http://www.opensource.org/licenses/bsd-license.html
# 
# Contributors:
#     Christopher Haines, Dale Scheppler, Nicholas Skaggs, Stephen V. Williams - initial API and implementation

# Set working directory
set -e

DIR=$(cd "$(dirname "$0")"; pwd)
cd $DIR
cd ..

HARVESTER_TASK=peoplesoft

if [ -f scripts/env ]; then
  . scripts/env
else
  exit 1
fi
echo "Full Logging in $HARVESTER_TASK.log"

BASEDIR=harvested-data/peoplesoft
RAWRHDIR=$BASEDIR/rh-raw
RAWRHDBURL=jdbc:h2:$RAWRHDIR/store
RDFRHDIR=$BASEDIR/rh-rdf
RDFRHDBURL=jdbc:h2:$RDFRHDIR/store
MODELDIR=$BASEDIR/model
MODELDBURL=jdbc:h2:$MODELDIR/store
SCOREDATADIR=$BASEDIR/score-data
SCOREDATADBURL=jdbc:h2:$SCOREDATADIR/store
TEMPCOPYDIR=$BASEDIR/temp-copy

#clear old fetches
rm -rf $RAWRHDIR

# Execute Fetch
$JDBCFetch -X config/tasks/PeopleSoftFetch.xml -o $TFRH -OfileDir=$RAWRHDIR
#-o $TFRH -OdbURL=$RAWRHDBURL

# backup fetch
BACKRAW="raw"
backup-path $RAWRHDIR $BACKRAW
# uncomment to restore previous fetch
#restore-path $RAWRHDIR $BACKRAW

exit

# clear old translates
rm -rf $RDFRHDIR

# Execute Translate
$XSLTranslator -i $TFRH -IfileDir=$RAWRHDIR -o $TFRH -OfileDir=$RDFRHDIR -x config/datamaps/peoplesoft-to-vivo.xsl

# backup translate
BACKRDF="rdf"
backup-path $RDFRHDIR $BACKRDF
# uncomment to restore previous translate
#restore-path $RDFRHDIR $BACKRDF

# Clear old H2 transfer model
rm -rf $MODELDIR

# Execute Transfer to import from record handler into local temp model
$Transfer -o $H2MODEL -OmodelName=peopleSoftTempTransfer -OcheckEmpty=$CHECKEMPTY -OdbUrl=$MODELDBURL -h $TFRH -HfileDir=$RDFRHDIR -n http://vivo.ufl.edu/individual/

# backup H2 transfer Model
BACKMODEL="model"
backup-path $MODELDIR $BACKMODEL
# uncomment to restore previous H2 transfer Model
#restore-path $MODELDIR $BACKMODEL

SCOREINPUT="-i $H2MODEL -ImodelName=peopleSoftTempTransfer -IdbUrl=$MODELDBURL -IcheckEmpty=$CHECKEMPTY"
SCOREDATA="-s $H2MODEL -SmodelName=peopleSoftScoreData -SdbUrl=$SCOREDATADBURL -ScheckEmpty=$CHECKEMPTY"
SCOREMODELS="$SCOREINPUT -v $VIVOCONFIG -VcheckEmpty=$CHECKEMPTY $SCOREDATA -t $TEMPCOPYDIR"
EQTEST="org.vivoweb.harvester.score.algorithm.EqualityTest"
UFID="http://vivo.ufl.edu/ontology/vivo-ufl/ufid"
UFDEPTID="http://vivo.ufl.edu/ontology/vivo-ufl/deptID"
POSINORG="http://vivoweb.org/ontology/core#positionInOrganization"
POSFORPERSON="http://vivoweb.org/ontology/core#positionForPerson"
UFPOSDEPTID="http://vivo.ufl.edu/ontology/vivo-ufl/deptIDofPosition"

# Clear old H2 score data
rm -rf $SCOREDATADIR

# Clear old H2 temp copy
rm -rf $TEMPCOPYDIR

# Execute Score for People
$Score $SCOREMODELS -n http://vivoweb.org/harvest/ufl/peoplesoft/person/ -Aufid=$EQTEST -Wufid=1.0 -Fufid=$UFID -Pufid=$UFID

# Execute Score for Departments
$Score $SCOREMODELS -n http://vivoweb.org/harvest/ufl/peoplesoft/org/ -AdeptId=$EQTEST -WdeptId=1.0 -FdeptId=$UFDEPTID -PdeptId=$UFDEPTID

# Find matches using scores and rename nodes to matching uri
$Match $SCOREINPUT $SCOREDATA -t 1.0 -r

# Execute Score for Positions
$Score $SCOREMODELS -n http://vivoweb.org/harvest/ufl/peoplesoft/position/ -AposOrg=$EQTEST -WposOrg=1.0 -FposOrg=$POSINORG -PposOrg=$POSINORG -AposPer=$EQTEST -WposPer=1.0 -FposPer=$POSFORPERSON -PposPer=$POSFORPERSON -AdeptPos=$EQTEST -WdeptPos=1.0 -FdeptPos=$UFPOSDEPTID -PdeptPos=$UFPOSDEPTID

# Find matches using scores and rename nodes to matching uri
$Match $SCOREINPUT $SCOREDATA -t 1.0 -r

# Clear old H2 temp copy
rm -rf $TEMPCOPYDIR

# backup H2 score data Model
BACKSCOREDATA="scoredata"
backup-path $SCOREDATADIR $BACKSCOREDATA
# uncomment to restore previous H2 matched Model
#restore-path $SCOREDATADIR $BACKSCOREDATA

CNFLAGS="$SCOREINPUT -v $VIVOCONFIG -VcheckEmpty=$CHECKEMPTY -n http://vivo.ufl.edu/individual/"
# Execute ChangeNamespace to get unmatched People into current namespace
$ChangeNamespace $CNFLAGS -o http://vivoweb.org/harvest/ufl/peoplesoft/person/
# Execute ChangeNamespace to get unmatched Departments into current namespace
$ChangeNamespace $CNFLAGS -o http://vivoweb.org/harvest/ufl/peoplesoft/org/ -e
# Execute ChangeNamespace to get unmatched Positions into current namespace
$ChangeNamespace $CNFLAGS -o http://vivoweb.org/harvest/ufl/peoplesoft/position/

# backup H2 matched Model
BACKMATCHED="matched"
backup-path $MODELDIR $BACKMATCHED
# uncomment to restore previous H2 matched Model
#restore-path $MODELDIR $BACKMATCHED

# Backup pretransfer vivo database, symlink latest to latest.sql
BACKPREDB="pretransfer"
backup-mysqldb $BACKPREDB
# uncomment to restore pretransfer vivo database
#restore-mysqldb $BACKPREDB

#PREVHARVESTMODEL="http://vivoweb.org/ingest/ufl/peoplesoft"
PREVHARVESTMODEL="uflPeopleSoft"
ADDFILE="$BASEDIR/additions.rdf.xml"
SUBFILE="$BASEDIR/subtractions.rdf.xml"

# Find Subtractions
$Diff -m $VIVOCONFIG -MmodelName=$PREVHARVESTMODEL -McheckEmpty=$CHECKEMPTY -s $H2MODEL -ScheckEmpty=$CHECKEMPTY -SdbUrl=$MODELDBURL -SmodelName=peopleSoftTempTransfer -d $SUBFILE
# Find Additions
$Diff -m $H2MODEL -McheckEmpty=$CHECKEMPTY -MdbUrl=$MODELDBURL -MmodelName=peopleSoftTempTransfer -s $VIVOCONFIG -ScheckEmpty=$CHECKEMPTY -SmodelName=$PREVHARVESTMODEL -d $ADDFILE

# Backup adds and subs
backup-file $ADDFILE adds.rdf.xml
backup-file $SUBFILE subs.rdf.xml

# Apply Subtractions to Previous model
$Transfer -o $VIVOCONFIG -OcheckEmpty=$CHECKEMPTY -OmodelName=$PREVHARVESTMODEL -r $SUBFILE -m
# Apply Additions to Previous model
$Transfer -o $VIVOCONFIG -OcheckEmpty=$CHECKEMPTY -OmodelName=$PREVHARVESTMODEL -r $ADDFILE
# Apply Subtractions to VIVO
$Transfer -o $VIVOCONFIG -OcheckEmpty=$CHECKEMPTY -r $SUBFILE -m
# Apply Additions to VIVO
$Transfer -o $VIVOCONFIG -OcheckEmpty=$CHECKEMPTY -r $ADDFILE

# Backup posttransfer vivo database, symlink latest to latest.sql
BACKPOSTDB="posttransfer"
backup-mysqldb $BACKPOSTDB
# uncomment to restore posttransfer vivo database
#restore-mysqldb $BACKPOSTDB

# Tomcat must be restarted in order for the harvested data to appear in VIVO
/etc/init.d/tomcat restart