# There's something in the opensc static libs that strip(1) invoked in the
# end of %%install doesn't grok.  Hence, disabled for now.
%define disable_static 1

%define plugindir %{_libdir}/mozilla/plugins

Name:           opensc
Version:        0.9.4
Release:        2
Summary:        OpenSC SmartCard library and applications

Group:          System Environment/Libraries
License:        LGPL
URL:            http://www.opensc.org/
Source0:        http://www.opensc.org/files/opensc-0.9.4.tar.gz
Patch0:         %{name}-build.patch
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildRequires:  pcsc-lite-devel >= 1.1.1 flex pam-devel openldap-devel
BuildRequires:  readline-devel libtermcap-devel openct-devel
BuildRequires:  openssl-devel >= 0.9.7a libassuan-devel XFree86-devel
# libtool (+ pulled in automake and autoconf) for patch0
BuildRequires:  libtool
Requires:       openct

%description
OpenSC is a package for for accessing SmartCard devices.  Basic
functionality (e.g. SELECT FILE, READ BINARY) should work on any ISO
7816-4 compatible SmartCard.  Encryption and decryption using private
keys on the SmartCard is possible with PKCS #15 compatible cards, such
as the FINEID (Finnish Electronic IDentity) card. Swedish Posten eID
cards have also been confirmed to work.

%package     -n mozilla-opensc-signer
Summary:        Digital signature plugin for web browsers
Group:          Applications/Internet
Requires:       %{plugindir} pinentry

%description -n mozilla-opensc-signer
OpenSC Signer is a plugin for web browsers compatible with Mozilla
plugins that will generate digital signatures using facilities on
PKI-capable smartcards.

%package        pam
Summary:        OpenSC pluggable authentication module
Group:          System Environment/Base
Provides:       pam_opensc = %{version}-%{release}
Requires:       %{name} = %{version}-%{release}

%description    pam
OpenSC pluggable authentication module implementing smart card support.

%package        devel
Summary:        OpenSC development files
Group:          Development/Libraries
Requires:       %{name} = %{version}-%{release} pkgconfig
Requires:       %{name}-pam = %{version}-%{release}

%description    devel
OpenSC development files.


%prep
%setup -q
%patch0 -p0
cp -p src/pkcs15init/README ./README.pkcs15init
cp -p src/scconf/README.scconf .
for file in docs/*.1 ; do
  iconv -f iso-8859-1 -t utf-8 $file > $file.utf-8 ; mv $file.utf-8 $file
done
sh ./bootstrap # for patch0


%build
%configure --disable-dependency-tracking \
%if %{disable_static}
  --disable-static \
%endif
  --with-plugin-dir=%{plugindir} \
  --with-pin-entry=%{_bindir}/pinentry
make %{?_smp_mflags}


%install
rm -rf $RPM_BUILD_ROOT _docs
make install DESTDIR=$RPM_BUILD_ROOT

# Fixup pam module location.
install -dm 755 $RPM_BUILD_ROOT/%{_lib}/security
mv $RPM_BUILD_ROOT%{_libdir}/security/pam_opensc.so \
  $RPM_BUILD_ROOT/%{_lib}/security/pam_opensc.so
rm -rf $RPM_BUILD_ROOT%{_libdir}/security

# Installing config examples as doc later.
install -dm 755 _docs/openssh
mv $RPM_BUILD_ROOT%{_datadir}/opensc/*.conf.example _docs
install -pm 644 src/openssh/README src/openssh/ask-for-pin.diff _docs/openssh


%clean
rm -rf $RPM_BUILD_ROOT


%post -p /sbin/ldconfig
%post pam -p /sbin/ldconfig
%postun -p /sbin/ldconfig
%postun pam -p /sbin/ldconfig


%files
%defattr(-,root,root,-)
%doc ANNOUNCE AUTHORS ChangeLog COPYING NEWS QUICKSTART README.*
%doc docs/*.html docs/*.css _docs/*.conf.example
%{_bindir}/cardos-info
%{_bindir}/cryptoflex-tool
%{_bindir}/opensc-explorer
%{_bindir}/opensc-tool
%{_bindir}/pkcs11-tool
%{_bindir}/pkcs15-crypt
%{_bindir}/pkcs15-init
%{_bindir}/pkcs15-tool
%{_libdir}/libopensc.so.*
%{_libdir}/libpkcs15init.so.*
%{_libdir}/libscconf.so.*
%{_libdir}/libscldap.so.*
%dir %{_libdir}/opensc
%{!?_with_oldssl:%{_libdir}/opensc/engine_*.so}
%dir %{_libdir}/pkcs11
%{_libdir}/pkcs11/opensc-pkcs11.so
%{_libdir}/pkcs11/lib*.so.*
%{_datadir}/opensc
%{_mandir}/man1/cardos-info.*
%{_mandir}/man1/cryptoflex-tool.*
%{_mandir}/man1/opensc-explorer.*
%{_mandir}/man1/opensc-tool.*
%{_mandir}/man1/pkcs11-tool.*
%{_mandir}/man1/pkcs15-crypt.*
%{_mandir}/man1/pkcs15-init.*
%{_mandir}/man1/pkcs15-tool.*
%{_mandir}/man[57]/*.[57]*

%files -n mozilla-opensc-signer
%defattr(0755,root,root,0755)
%{plugindir}/opensc-signer.so
%{_libdir}/opensc/opensc-signer.so

%files pam
%defattr(-,root,root,-)
%doc PAM_README
/%{_lib}/security/pam_opensc.so
%{_libdir}/libscam.so.*

%files devel
%defattr(-,root,root,-)
%doc CodingStyle _docs/openssh
%{_bindir}/opensc-config
%{_includedir}/opensc
%exclude %{_libdir}/*.la
%{_libdir}/libopensc.so
%{_libdir}/libpkcs15init.so
%{_libdir}/libscam.so
%{_libdir}/libscconf.so
%{_libdir}/libscldap.so
%exclude %{_libdir}/opensc/*.la
%{_libdir}/pkcs11/pkcs11-spy.so
%{_libdir}/pkcs11/lib*.so
%exclude %{_libdir}/pkcs11/*.la
%{_libdir}/pkgconfig/libopensc.pc
%{_mandir}/man1/opensc-config.1*
%{_mandir}/man3/*.3*
%if !%{disable_static}
%{_libdir}/*.a
%{_libdir}/opensc/*.a
%{_libdir}/pkcs11/lib*.a
%endif


%changelog
* Wed Feb  9 2005 Michael Schwendt <mschwendt[AT]users.sf.net> - 0.9.4-2
- Use --with-plugin-dir instead of --with-plugin-path (fixes x86_64).

* Thu Feb  3 2005 Ville Skyttä <ville.skytta at iki.fi> - 0.9.4-1
- Drop unnecessary Epochs, pre-FC1 compat cruft, and no longer relevant
  --with(out) rpmbuild options.
- Exclude *.la.

* Wed Nov  3 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:0.9.4-0.fdr.1
- Update to 0.9.4, parallel build patch applied upstream.
- Patch to fix library paths and LDFLAGS.
- Don't require mozilla, but the plugin dir in signer.
- Build with dependency tracking disabled.

* Tue Jul 27 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:0.9.2-0.fdr.2
- Building the signer plugin can be disabled with "--without signer".
  Thanks to Fritz Elfert for the idea.
- Update description.

* Sun Jul 25 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:0.9.2-0.fdr.1
- Update to 0.9.2, old patches applied upstream.
- Add patch to fix parallel builds.
- Convert man pages to UTF-8.

* Thu Jul 22 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:0.9.1-0.fdr.1
- Update to 0.9.1 (preview).

* Thu Jul  1 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:0.9.0-0.fdr.0.1.alpha
- Update to 0.9.0-alpha.

* Sat May  1 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:0.8.1-0.fdr.8
- Rebuild with libassuan 0.6.5.

* Sat Jan 31 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:0.8.1-0.fdr.7
- Rebuild with libassuan 0.6.3.
- Add gdm example to PAM quickstart.

* Mon Jan 19 2004 Ville Skyttä <ville.skytta at iki.fi> - 0:0.8.1-0.fdr.6
- Use /%%{_lib} instead of hardcoding /lib.

* Sat Dec 20 2003 Ville Skyttä <ville.skytta at iki.fi> - 0:0.8.1-0.fdr.5
- Split PAM support into a subpackage.
- Rebuild with libassuan 0.6.2.

* Sun Nov 23 2003 Ville Skyttä <ville.skytta at iki.fi> - 0:0.8.1-0.fdr.4
- Rebuild with libassuan 0.6.1.
- Include PAM quickstart doc snippet.

* Fri Nov 14 2003 Ville Skyttä <ville.skytta at iki.fi> - 0:0.8.1-0.fdr.3
- Require OpenCT.

* Fri Oct 17 2003 Ville Skyttä <ville.skytta at iki.fi> - 0:0.8.1-0.fdr.2
- Install example config files as documentation.

* Tue Oct 14 2003 Ville Skyttä <ville.skytta at iki.fi> - 0:0.8.1-0.fdr.1
- Update to 0.8.1.

* Wed Aug 27 2003 Ville Skyttä <ville.skytta at iki.fi> - 0:0.8.0-0.fdr.2
- Signer can be built with oldssl too.

* Wed Aug 27 2003 Ville Skyttä <ville.skytta at iki.fi> - 0:0.8.0-0.fdr.1
- Update to 0.8.0.

* Wed Jul 30 2003 Ville Skyttä <ville.skytta at iki.fi> - 0:0.8.0-0.fdr.0.2.cvs20030730
- Update to 20030730.
- Clean up %%docs.
- Include *.la (uses ltdl).
- Own the %%{_libdir}/pkcs11 directory.
- Disable signer; assuan has disappeared from the tarball :(

* Fri May 23 2003 Ville Skyttä <ville.skytta at iki.fi> - 0:0.8.0-0.fdr.0.1.rc1
- First build.
