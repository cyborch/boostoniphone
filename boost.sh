#===============================================================================
# Filename:  boost.sh
# Author:    Pete Goodliffe
# Copyright: (c) Copyright 2009 Pete Goodliffe
# Licence:   Please feel free to use this, with attribution
#===============================================================================
#
# Builds a Boost framework for the iPhone.
# Creates a set of universal libraries that can be used on an iPhone and in the
# iPhone simulator. Then creates a pseudo-framework to make using boost in Xcode
# less painful.
#
# To configure the script, define:
#    BOOST_LIBS:        which libraries to build
#    IPHONE_SDKVERSION: iPhone SDK version (e.g. 5.1)
#
# Then go get the source tar.bz of the boost you want to build, shove it in the
# same directory as this script, and run "./boost.sh". Grab a cuppa. And voila.
#===============================================================================

: ${BOOST_LIBS:="thread signals filesystem regex system date_time"}
: ${IPHONE_SDKVERSION:=6.1}
: ${OSX_SDKVERSION:=10.8}
: ${XCODE_ROOT:=`xcode-select -print-path`}
: ${EXTRA_CPPFLAGS:="-DBOOST_AC_USE_PTHREADS -DBOOST_SP_USE_PTHREADS -std=c++11 -stdlib=libc++"}

# The EXTRA_CPPFLAGS definition works around a thread race issue in
# shared_ptr. I encountered this historically and have not verified that
# the fix is no longer required. Without using the posix thread primitives
# an invalid compare-and-swap ARM instruction (non-thread-safe) was used for the
# shared_ptr use count causing nasty and subtle bugs.
#
# Should perhaps also consider/use instead: -BOOST_SP_USE_PTHREADS

: ${SRCDIR:=`pwd`}
: ${IOSBUILDDIR:=`pwd`/ios/build}
: ${OSXBUILDDIR:=`pwd`/osx/build}
: ${PREFIXDIR:=`pwd`/ios/prefix}
: ${IOSFRAMEWORKDIR:=`pwd`/ios/framework}
: ${OSXFRAMEWORKDIR:=`pwd`/osx/framework}
: ${COMPILER:="clang++"}

BOOST_SRC=$SRCDIR/boost

#===============================================================================

ARM_DEV_DIR=$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer/usr/bin/
SIM_DEV_DIR=$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/usr/bin/

ARM_COMBINED_LIB=$IOSBUILDDIR/lib_boost_arm.a
SIM_COMBINED_LIB=$IOSBUILDDIR/lib_boost_x86.a

#===============================================================================


#===============================================================================
# Functions
#===============================================================================

abort()
{
    echo
    echo "Aborted: $@"
    exit 1
}

doneSection()
{
    echo
    echo "    ================================================================="
    echo "    Done"
    echo
}

#===============================================================================

cleanEverythingReadyToStart()
{
    echo Cleaning everything before we start to build...
	rm -rf iphone-build iphonesim-build osx-build
    rm -rf $IOSBUILDDIR
    rm -rf $OSXBUILDDIR
    rm -rf $PREFIXDIR
    rm -rf $IOSFRAMEWORKDIR/$FRAMEWORK_NAME.framework
    rm -rf $OSXFRAMEWORKDIR/$FRAMEWORK_NAME.framework
    doneSection
}

#===============================================================================
updateBoost()
{
    echo Updating boost into $BOOST_SRC...

	if [ -d $BOOST_SRC ]
	then
		# Remove everything not under version control...
		svn st --no-ignore $BOOST_SRC | egrep '^[?I]' | sed 's:.......::' | xargs rm -rf 
		svn update boost
	else
		BOOST_BRANCH=`svn ls http://svn.boost.org/svn/boost/tags/release/ | sort | tail -1`
		svn co http://svn.boost.org/svn/boost/tags/release/$BOOST_BRANCH boost
	fi

	svn st $BOOST_SRC/tools/build/v2/user-config.jam | grep '^M'
	if [ $? != 0 ]
	then
    	cat >> $BOOST_SRC/tools/build/v2/user-config.jam <<EOF
using darwin : ${IPHONE_SDKVERSION}~iphone
   : $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/$COMPILER -arch armv6 -arch armv7 -arch armv7s -fvisibility=hidden -fvisibility-inlines-hidden $EXTRA_CPPFLAGS
   : <striper> <root>$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer
   : <architecture>arm <target-os>iphone
   ;
using darwin : ${IPHONE_SDKVERSION}~iphonesim
   : $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/$COMPILER -arch i386 -fvisibility=hidden -fvisibility-inlines-hidden $EXTRA_CPPFLAGS
   : <striper> <root>$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer
   : <architecture>x86 <target-os>iphone
   ;
EOF
	fi

    doneSection
}

#===============================================================================

inventMissingHeaders()
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo Invent missing headers
    cp $XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IPHONE_SDKVERSION}.sdk/usr/include/{crt_externs,bzlib}.h $BOOST_SRC
}

#===============================================================================

bootstrapBoost()
{
    cd $BOOST_SRC
    BOOST_LIBS_COMMA=$(echo $BOOST_LIBS | sed -e "s/ /,/g")
    echo "Bootstrapping (with libs $BOOST_LIBS_COMMA)"
    ./bootstrap.sh --with-libraries=$BOOST_LIBS_COMMA
    doneSection
}

#===============================================================================

buildBoostForiPhoneOS()
{
    cd $BOOST_SRC
    
	# Install this one so we can copy the includes for the frameworks...
    ./bjam -j16 --build-dir=../iphone-build --stagedir=../iphone-build/stage --prefix=$PREFIXDIR toolset=darwin architecture=arm target-os=iphone macosx-version=iphone-${IPHONE_SDKVERSION} define=_LITTLE_ENDIAN link=static stage
    ./bjam -j16 --build-dir=../iphone-build --stagedir=../iphone-build/stage --prefix=$PREFIXDIR toolset=darwin architecture=arm target-os=iphone macosx-version=iphone-${IPHONE_SDKVERSION} define=_LITTLE_ENDIAN link=static install
    doneSection

    ./bjam -j16 --build-dir=../iphonesim-build --stagedir=../iphonesim-build/stage --toolset=darwin architecture=x86 target-os=iphone macosx-version=iphonesim-${IPHONE_SDKVERSION} link=static stage
	doneSection

	./b2 -j16 --build-dir=../osx-build --stagedir=../osx-build/stage toolset=clang cxxflags="-std=c++11 -stdlib=libc++ -arch i386 -arch x86_64" linkflags="-stdlib=libc++" link=static threading=multi stage
    doneSection
}

#===============================================================================

scrunchAllLibsTogetherInOneLibPerPlatform()
{
	cd $SRCDIR

    mkdir -p $IOSBUILDDIR/armv6/obj
    mkdir -p $IOSBUILDDIR/armv7/obj
    mkdir -p $IOSBUILDDIR/armv7s/obj
    mkdir -p $IOSBUILDDIR/i386/obj

    mkdir -p $OSXBUILDDIR/i386/obj
    mkdir -p $OSXBUILDDIR/x86_64/obj

    ALL_LIBS=""

    echo Splitting all existing fat binaries...
    for NAME in $BOOST_LIBS; do
        ALL_LIBS="$ALL_LIBS libboost_$NAME.a"

        $ARM_DEV_DIR/lipo "iphone-build/stage/lib/libboost_$NAME.a" -thin armv6 -o $IOSBUILDDIR/armv6/libboost_$NAME.a
        $ARM_DEV_DIR/lipo "iphone-build/stage/lib/libboost_$NAME.a" -thin armv7 -o $IOSBUILDDIR/armv7/libboost_$NAME.a
        $ARM_DEV_DIR/lipo "iphone-build/stage/lib/libboost_$NAME.a" -thin armv7s -o $IOSBUILDDIR/armv7s/libboost_$NAME.a

        cp "iphonesim-build/stage/lib/libboost_$NAME.a" $IOSBUILDDIR/i386/

        $ARM_DEV_DIR/lipo "osx-build/stage/lib/libboost_$NAME.a" -thin i386 -o $OSXBUILDDIR/i386/libboost_$NAME.a
        $ARM_DEV_DIR/lipo "osx-build/stage/lib/libboost_$NAME.a" -thin x86_64 -o $OSXBUILDDIR/x86_64/libboost_$NAME.a
    done

    echo "Decomposing each architecture's .a files"
    for NAME in $ALL_LIBS; do
        echo Decomposing $NAME...
        (cd $IOSBUILDDIR/armv6/obj; ar -x ../$NAME );
        (cd $IOSBUILDDIR/armv7/obj; ar -x ../$NAME );
        (cd $IOSBUILDDIR/armv7s/obj; ar -x ../$NAME );
        (cd $IOSBUILDDIR/i386/obj; ar -x ../$NAME );

        (cd $OSXBUILDDIR/i386/obj; ar -x ../$NAME );
        (cd $OSXBUILDDIR/x86_64/obj; ar -x ../$NAME );
    done

    echo "Linking each architecture into an uberlib ($ALL_LIBS => libboost.a )"
    rm $IOSBUILDDIR/*/libboost.a
    echo ...armv6
    (cd $IOSBUILDDIR/armv6; $ARM_DEV_DIR/ar crus libboost.a obj/*.o; )
    echo ...armv7
    (cd $IOSBUILDDIR/armv7; $ARM_DEV_DIR/ar crus libboost.a obj/*.o; )
    echo ...armv7s
    (cd $IOSBUILDDIR/armv7s; $ARM_DEV_DIR/ar crus libboost.a obj/*.o; )
    echo ...i386
    (cd $IOSBUILDDIR/i386;  $SIM_DEV_DIR/ar crus libboost.a obj/*.o; )

    rm $OSXBUILDDIR/*/libboost.a
    echo ...osx-i386
    (cd $OSXBUILDDIR/i386;  $SIM_DEV_DIR/ar crus libboost.a obj/*.o; )

    echo ...x86_64
    (cd $OSXBUILDDIR/x86_64;  $SIM_DEV_DIR/ar crus libboost.a obj/*.o; )
}

#===============================================================================
buildFramework()
{
	: ${1:?}
	FRAMEWORKDIR=$1
	BUILDDIR=$2

	VERSION_TYPE=Alpha
	FRAMEWORK_NAME=boost
	FRAMEWORK_VERSION=A

	FRAMEWORK_CURRENT_VERSION=$BOOST_VERSION
	FRAMEWORK_COMPATIBILITY_VERSION=$BOOST_VERSION

    FRAMEWORK_BUNDLE=$FRAMEWORKDIR/$FRAMEWORK_NAME.framework
    echo "Framework: Building $FRAMEWORK_BUNDLE from $BUILDDIR..."

    rm -rf $FRAMEWORK_BUNDLE

    echo "Framework: Setting up directories..."
    mkdir -p $FRAMEWORK_BUNDLE
    mkdir -p $FRAMEWORK_BUNDLE/Versions
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Resources
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Headers
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Documentation

    echo "Framework: Creating symlinks..."
    ln -s $FRAMEWORK_VERSION               $FRAMEWORK_BUNDLE/Versions/Current
    ln -s Versions/Current/Headers         $FRAMEWORK_BUNDLE/Headers
    ln -s Versions/Current/Resources       $FRAMEWORK_BUNDLE/Resources
    ln -s Versions/Current/Documentation   $FRAMEWORK_BUNDLE/Documentation
    ln -s Versions/Current/$FRAMEWORK_NAME $FRAMEWORK_BUNDLE/$FRAMEWORK_NAME

    FRAMEWORK_INSTALL_NAME=$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME

    echo "Lipoing library into $FRAMEWORK_INSTALL_NAME..."
    $ARM_DEV_DIR/lipo -create $BUILDDIR/*/libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"

    echo "Framework: Copying includes..."
    cp -r $PREFIXDIR/include/boost/*  $FRAMEWORK_BUNDLE/Headers/

    echo "Framework: Creating plist..."
    cat > $FRAMEWORK_BUNDLE/Resources/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleExecutable</key>
	<string>${FRAMEWORK_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>org.boost</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>${FRAMEWORK_CURRENT_VERSION}</string>
</dict>
</plist>
EOF
    doneSection
}

#===============================================================================
# Execution starts here
#===============================================================================

mkdir -p $IOSBUILDDIR

cleanEverythingReadyToStart
updateBoost

BOOST_VERSION=`svn info $BOOST_SRC | grep URL | sed -e 's/^.*\/Boost_\([^\/]*\)/\1/'`
echo "BOOST_VERSION:     $BOOST_VERSION"
echo "BOOST_LIBS:        $BOOST_LIBS"
echo "BOOST_SRC:         $BOOST_SRC"
echo "IOSBUILDDIR:       $IOSBUILDDIR"
echo "OSXBUILDDIR:       $OSXBUILDDIR"
echo "PREFIXDIR:         $PREFIXDIR"
echo "IOSFRAMEWORKDIR:   $IOSFRAMEWORKDIR"
echo "OSXFRAMEWORKDIR:   $OSXFRAMEWORKDIR"
echo "IPHONE_SDKVERSION: $IPHONE_SDKVERSION"
echo "XCODE_ROOT:        $XCODE_ROOT"
echo "COMPILER:          $COMPILER"
echo

inventMissingHeaders
bootstrapBoost
buildBoostForiPhoneOS
scrunchAllLibsTogetherInOneLibPerPlatform
buildFramework $IOSFRAMEWORKDIR $IOSBUILDDIR
buildFramework $OSXFRAMEWORKDIR $OSXBUILDDIR

echo "Completed successfully"

#===============================================================================
