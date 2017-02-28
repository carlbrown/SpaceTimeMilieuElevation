#!/bin/bash

swift package fetch
swift package edit Kitura --revision swift-3.1
swift package edit HeliumLogger  --revision 1.6.0
patch -p1 < NetHack.diff 
swift build
