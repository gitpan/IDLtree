#!/usr/bin/perl
#
# idl2ada.pl:       IDL symbol tree to Ada95 translator
# Version:          0.4
# Supported CORBA systems:
#                   * ORBit (ftp://ftp.gnome.org/pub/ORBit/)
#          NOT YET: * TAO (http://www.cs.wustl.edu/~schmidt/TAO.html)
#                     Uses GNAT specific C++ interfacing pragmas; currently
#                     client side only due to problem with GNAT 3.11p C++
#                     interfacing
# Requires:         Perl5 module CORBA::IDLtree
# Author/Copyright: Oliver M. Kellogg (kellogg@vs.dasa.de)
#
# This file is part of GNACK, the GNU Ada CORBA Kit.
#
# GNACK is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# GNACK is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#

use CORBA::IDLtree;

# Subroutine forward declarations

sub gen_ada;
sub gen_ada_recursive;
sub mapped_type;
sub isnode;       # shorthand for isnode
sub is_complex;   # returns 0 if representation of struct is same in C and Ada
sub is_objref;
sub ada_from_c_var;
sub c_from_ada_var;
sub c2adatype;
sub ada2ctype;
sub check_features_used;
sub open_files;
# Emit subroutines
sub epspec;     # emit to proxy spec
sub epbody;     # emit to proxy body
sub epboth;     # emit to both proxy spec and proxy body
sub eispec;     # emit to impl spec
sub eibody;     # emit to impl body
sub eiboth;     # emit to both impl spec and body
sub eospec;     # emit to POA spec
sub eobody;     # emit to POA body
sub eoboth;     # emit to both POA spec and body
sub ehspec;     # emit to helper spec
sub ehbody;     # emit to helper body
sub ehboth;     # emit to both helper spec and body
sub epispec;    # emit to proxy and impl spec
sub epibody;    # emit to proxy and impl body
sub epospec;    # emit to proxy and POA spec
sub epobody;    # emit to proxy and POA body
sub eall;       # emit to all files except the POA body
# Print subroutines (print is same as emit, but with indentation)
sub ppspec;     # print to proxy spec
sub ppbody;     # print to proxy body
sub ppboth;     # print to both proxy spec and proxy body
sub pispec;     # print to impl spec
sub pibody;     # print to impl body
sub piboth;     # print to both impl spec and body
sub pospec;     # print to POA spec
sub pobody;     # print to POA body
sub poboth;     # print to both POA spec and body
sub ppispec;    # print to proxy and impl spec
sub ppibody;    # print to proxy and impl body
sub ppospec;    # print to proxy and POA spec
sub ppobody;    # print to proxy and POA body
sub pall;       # print to all files except the POA body
sub pospecbuf;  # print to $poaspecbuf
sub specindent;
sub specdedent;
sub print_pkg_prologues;
sub print_spec_interface;
sub print_body_interface;
sub print_ispec_interface;
sub print_ibody_interface;
sub print_interface_prologues;


# Constants

# possible target systems
$ORBIT = 0;
$TAO = 1;
# shorthands for frequently used constants from CORBA::IDLtree
$NAME = $CORBA::IDLtree::NAME;
$TYPE = $CORBA::IDLtree::TYPE;
$SUBORDINATES = $CORBA::IDLtree::SUBORDINATES;
$MODE = $SUBORDINATES;
$SCOPEREF = $CORBA::IDLtree::SCOPEREF;
$GEN_C_TYPE = $CORBA::IDLtree::LANG_C;
# number of spaces for one indentation
$INDENT = 3;
# number of indents for an approx. 1/3-page (25 space) indentation
$INDENT2 = (1 << (5 - $INDENT)) + 4;
# file handles
@proxy_spec_file_handle = qw/ PS0 PS1 PS2 PS3 PS4 PS5 PS6 PS7 PS8 PS9 /;
@proxy_body_file_handle = qw/ PB0 PB1 PB2 PB3 PB4 PB5 PB6 PB7 PB8 PB9 /;
@impl_spec_file_handle  = qw/ IS0 IS1 IS2 IS3 IS4 IS5 IS6 IS7 IS8 IS9 /;
@impl_body_file_handle  = qw/ IB0 IB1 IB2 IB3 IB4 IB5 IB6 IB7 IB8 IB9 /;
@poa_spec_file_handle   = qw/ OA0 OA1 OA2 OA3 OA4 OA5 OA6 OA7 OA8 OA9 /;
@poa_body_file_handle   = qw/ OB0 OB1 OB2 OB3 OB4 OB5 OB6 OB7 OB8 OB9 /;
@hlp_spec_file_handle   = qw/ HS0 HS1 HS2 HS3 HS4 HS5 HS6 HS7 HS8 HS9 /;
@hlp_body_file_handle   = qw/ HB0 HB1 HB2 HB3 HB4 HB5 HB6 HB7 HB8 HB9 /;
    # The file handles are indexed by $#scopestack.

# Global variables
$target_system = $ORBIT;
@gen_ispec = ();     # Generate implementation package spec (see gen_ada)
@gen_ibody = ();     # Generate implementation package body (see gen_ada)
@spec_ilvl = ();     # Proxy-spec indentlevel
@body_ilvl = ();     # Proxy-body indentlevel
@ispec_ilvl = ();    # Impl-spec indentlevel
@ibody_ilvl = ();    # Impl-body indentlevel
@poa_ilvl = ();      # POA-indentlevel (valid for both spec and body)
@scopestack = ();    # Stack of module/interface names
@withlist = ();      # List of user packages to "with"
%helpers = ();       # Names that have helper packages
%strbound = ();      # Bound numbers of bounded strings
@opened_helper = (); # Stack of flags; moves in parallel with @scopestack;
                     # true when helper file has been opened
$poaspecbuf = "";    # POA spec file output buffer
$poaspecbuf_enabled = 0;     # enable(disable=0) output to POA spec buffer
$did_file_prologues = 0;     # Flag; true when prologues were already written
$global_scope_pkgname = "";  # only set if _IDL_File synthesis required
$pragprefix = "";    # the name given in a #pragma prefix, suffixed with '/'
$psfh = 0;           # Shorthand for $proxy_spec_file_handle[$#scopestack]
$pbfh = 0;           # Shorthand for $proxy_body_file_handle[$#scopestack]
$isfh = 0;           # Shorthand for $impl_spec_file_handle[$#scopestack]
$ibfh = 0;           # Shorthand for $impl_body_file_handle[$#scopestack]
$osfh = 0;           # Shorthand for $poa_spec_file_handle[$#scopestack]
$obfh = 0;           # Shorthand for $poa_body_file_handle[$#scopestack]
$hsfh = 0;           # Shorthand for $hlp_spec_file_handle[$#scopestack]
$hbfh = 0;           # Shorthand for $hlp_body_file_handle[$#scopestack]
# feature flags
# TO BE REFINED! These should be on a per-interface basis
$need_unbounded_seq = 0;
$need_bounded_seq = 0;
$need_exceptions = 0;

# Options processing
$verbose = 0;
for ($i=0; $i <= $#ARGV; $i++) {
    if ($ARGV[$i] =~ /^-/) {
        for (substr($ARGV[$i], 1)) {
            /^orbit$/i  and $target_system = $ORBIT, last;
            /^tao$/i    and $target_system = $TAO, last;
            /^v$/       and $verbose = 1, last;
            /^V$/       and print("idl2ada version 0.1b\n"), last;
            die "unknown option: $ARGV[$i]\n";
        }
        splice(@ARGV, $i--, 1);
    }
}

# Main program

while (@ARGV) {
    $idl_filename = shift @ARGV;
        # $idl_filename is global and might be used in gen_ada for generating
        # the _IDL_File global-scope package.
    my $symroot = CORBA::IDLtree::Parse_File $idl_filename;
    die "idl2ada: errors while parsing $idl_filename\n" unless ($symroot);
    CORBA::IDLtree::Dump_Symbols($symroot) if ($verbose);
    gen_ada $symroot;
}

# End of main program


# Ada back end subroutines

sub epspec {
    my $text = shift;
    print $psfh $text;
}

sub epbody {
    my $text = shift;
    print $pbfh $text;
}

sub epboth {
    my $text = shift;
    epspec $text;
    epbody $text;
}

sub eispec {
    my $text = shift;
    if ($gen_ispec[$#scopestack]) {
        print $isfh $text;
    }
}

sub eibody {
    my $text = shift;
    if ($gen_ibody[$#scopestack]) {
        print $ibfh $text;
    }
}

sub eiboth {
    my $text = shift;
    eispec $text;
    eibody $text;
}

sub eospec {
    my $text = shift;
    print $osfh $text;
}

sub eospecbuf {
    $poaspecbuf .= shift;
}

sub eobody {
    my $text = shift;
    print $obfh $text;
    if ($poaspecbuf_enabled > 1) {   # Beware: output might also go to the
        eospecbuf $text;             # POA spec buffer
    }
}

sub eoboth {
    my $text = shift;
    eospec $text;
    eobody $text;
}

sub epispec {
    my $text = shift;
    epspec $text;
    eispec $text;
}

sub epibody {
    my $text = shift;
    epbody $text;
    eibody $text;
}

sub epospec {
    my $text = shift;
    epspec $text;
    if ($poaspecbuf_enabled) {
        eospecbuf $text;
    } else {
        eospec $text;
    }
}

sub epobody {
    my $text = shift;
    epbody $text;
    eobody $text;
}

sub eall {
    my $text = shift;
    epispec $text;
    epibody $text;
    eospec $text;
    if ($poaspecbuf_enabled > 1) {   # Beware: output might also go to the
        eospecbuf $text;             # POA spec buffer
    }
}

sub ehspec {
    my $text = shift;
    print $hsfh $text;
}

sub ehbody {
    my $text = shift;
    print $hbfh $text;
}

sub ehboth {
    my $text = shift;
    ehspec $text;
    ehbody $text;
}


sub ppspec {
    my $text = (' ' x ($INDENT * $spec_ilvl[$#spec_ilvl])) . shift;
    epspec $text;
}

sub ppbody {
    my $text = (' ' x ($INDENT * $body_ilvl[$#body_ilvl])) . shift;
    epbody $text;
}

sub ppboth {
    my $text = shift;
    ppspec $text;
    ppbody $text;
}

sub pispec {
    my $text = (' ' x ($INDENT * $ispec_ilvl[$#ispec_ilvl])) . shift;
    eispec $text;
}

sub pibody {
    my $text = (' ' x ($INDENT * $ibody_ilvl[$#ibody_ilvl])) . shift;
    eibody $text;
}

sub piboth {
    my $text = shift;
    pispec $text;
    pibody $text;
}

sub pospec {
    my $text = (' ' x ($INDENT * $poa_ilvl[$#poa_ilvl])) . shift;
    eospec $text;
}

sub pobody {
    my $text = (' ' x ($INDENT * $poa_ilvl[$#poa_ilvl])) . shift;
    eobody $text;
}

sub poboth {
    my $text = shift;
    if (! $poaspecbuf_enabled) {
        pospec $text;
    }
    pobody $text;
}

sub ppispec {
    my $text = shift;
    ppspec $text;
    pispec $text;
}

sub ppibody {
    my $text = shift;
    ppbody $text;
    pibody $text;
}

sub ppospec {
    my $text = shift;
    ppspec $text;
    pospec $text;
}

sub pospecbuf {
    my $text = (' ' x ($INDENT * $poa_ilvl[$#poa_ilvl])) . shift;
    eospecbuf $text;
}

sub ppobody {
    my $text = shift;
    ppbody $text;
    pobody $text;
}

sub pall {
    my $text = shift;
    ppispec $text;
    ppibody $text;
    pospec $text;
    if ($poaspecbuf_enabled > 1) {   # Beware: output might also go to the
        pospecbuf $text;             # POA spec buffer
    }
}

sub specindent {
    ppspec shift;
    $spec_ilvl[$#spec_ilvl]++;
}

sub specdedent {
    $spec_ilvl[$#spec_ilvl]--;
    ppspec shift;
}

$overwrite_warning =
      "----------------------------------------------------------------\n"
    . "-- WARNING:  This is generated Ada source that is automatically\n"
    . "--           overwritten when idl2ada.pl is run.\n"
    . "--           Changes to this file will be lost.\n"
    . "----------------------------------------------------------------\n\n";

sub print_specfile_prologue {
    my $pkgname = shift;
    ppspec $overwrite_warning;
    if ($need_exceptions) {
        ppspec "with Ada.Exceptions;\n";
    }
    ppspec "with CORBA, CORBA.Object, CORBA.C_Types;\n";
    if ($need_unbounded_seq) {
        ppspec "with CORBA.Sequences.Unbounded;\n";
    }
    if ($need_bounded_seq) {
        ppspec "with CORBA.Sequences.Bounded;\n";
    }
    # ppspec "with CORBA.InterfaceDef;\n";
    # ppspec "with CORBA.ImplementationDef;\n";
    foreach $bound (keys %strbound) {
        ppspec "with CORBA.Bounded_String_$bound;\n";
    }
    epspec "\n";
}

sub print_bodyfile_prologue {
    my $pkgname = shift;
    ppbody $overwrite_warning;
    ppbody "with System;\n";
    if ($need_exceptions) {
        ppbody "with System.Storage_Elements;\n";
        ppbody "with System.Address_To_Access_Conversions;\n";
    }
    ppbody "with C_Strings;\n";
    ppbody "with CORBA.Environment;\n";
    foreach $hlppkg (keys %helpers) {
        ppbody "with $hlppkg\.Helper;\n";
    }
    epbody "\n";
}

sub print_ospecfile_prologue {
    my $pkgname = shift;
    pospec $overwrite_warning;
    pospec "with System, C_Strings;\n";
    pospec "with CORBA, CORBA.Object, CORBA.C_Types, CORBA.Environment;\n";
    pospec "with PortableServer.ServantBase;\n";
    pospec "with $pkgname;\n";
    foreach $hlppkg (keys %helpers) {
        pospec "with $hlppkg\.Helper;\n";
    }
    pospec "use  $pkgname;\n\n";
}

sub print_obodyfile_prologue {
    my $pkgname = shift;
    pobody $overwrite_warning;
    pobody "with System;\n";
    if ($need_exceptions) {
        pobody "with System.Storage_Elements;\n";
        pobody "with System.Address_To_Access_Conversions;\n";
        pobody "with Ada.Exceptions;\n";
    }
    pobody "with PortableServer.ServantBase.C_Map;\n";
    pobody "\n";
}

sub print_ispecfile_prologue {
    my $pkgname = shift;
    pispec "----------------------------------------------------------------\n";
    pispec "-- $pkgname\.Impl (spec)\n";
    pispec "--\n";
    pispec "-- This file will not be overwritten by idl2ada.pl\n";
    pispec "----------------------------------------------------------------\n";
    pispec "\n";
    pispec "with POA_$pkgname;\n\n";
}

sub print_ibodyfile_prologue {
    my $pkgname = shift;
    pibody "----------------------------------------------------------------\n";
    pibody "-- $pkgname\.Impl (body)\n";
    pibody "--\n";
    pibody "-- This file will not be overwritten by idl2ada.pl\n";
    pibody "----------------------------------------------------------------\n";
    pibody "\n\n";
}


sub print_withlist {
    my $root_pkg = shift;
    $root_pkg =~ s/\..*//;
    if (@withlist) {
        my $first = 1;
        foreach $w (@withlist) {
            next if ($w eq $root_pkg);
            if ($first) {
                epispec "with";
                $first = 0;
            } else {
                epispec ',';
            }
            epispec " $w";
        }
        if (! $first) {
            epispec ";\n\n";
        }
        # POA file output
        foreach $w (@withlist) {
            eospec "with $w;\n";
        }
        eospec "\n";
    }
}


sub print_pkg_prologues {
    my $pkgname = shift;
    my $is_module = 0;
    if (@_) {
        $is_module = shift;
    }
    push @spec_ilvl, 0;
    push @body_ilvl, 0;
    print_specfile_prologue($pkgname, $is_module);
    print_bodyfile_prologue($pkgname, $is_module);
    push @poa_ilvl, 0;
    print_ospecfile_prologue($pkgname);
    print_obodyfile_prologue($pkgname);
    if (! $is_module) {
        if ($gen_ispec[$#scopestack]) {
            push @ispec_ilvl, 0;
            print_ispecfile_prologue($pkgname);
        }
        if ($gen_ibody[$#scopestack]) {
            push @ibody_ilvl, 0;
            print_ibodyfile_prologue($pkgname);
        }
    }
    print_withlist $pkgname;
    push @withlist, $pkgname;
}


sub print_pkg_decl {
    my $name = shift;
    specindent "package $name is\n\n";
    ppbody "package body $name is\n\n";
    $body_ilvl[$#body_ilvl]++;
    pospec "package POA_$name is\n\n";
    pobody "package body POA_$name is\n\n";
    $poa_ilvl[$#poa_ilvl]++;

    if ($gen_ispec[$#scopestack]) {
        pispec "package $name\.Impl is\n\n";
        $ispec_ilvl[$#ispec_ilvl]++;
    }
    if ($gen_ibody[$#scopestack]) {
        pibody "package body $name\.Impl is\n\n";
        $ibody_ilvl[$#ibody_ilvl]++;
    }
}

sub finish_pkg_decl {
    my $name = shift;
    my $spartan = 0;
    if (@_) {
        $spartan = 1;
    }
    specdedent "end $name;\n\n";
    close $psfh;
    $body_ilvl[$#body_ilvl]--;
    ppbody "end $name;\n\n";
    close $pbfh;
    $poa_ilvl[$#poa_ilvl]--;
    poboth "end POA_$name;\n\n";
    close $osfh;
    close $obfh;
    if ($spartan) {
        return;
    }
    pop @spec_ilvl;
    pop @body_ilvl;
    pop @poa_ilvl;
    if ($gen_ispec[$#scopestack]) {
        $ispec_ilvl[$#ispec_ilvl]--;
        pispec "end $name\.Impl;\n\n";
        close $isfh;
        pop @ispec_ilvl;
    }
    if ($gen_ibody[$#scopestack]) {
        $ibody_ilvl[$#ibody_ilvl]--;
        pibody "end $name\.Impl;\n\n";
        close $ibfh;
        pop @ibody_ilvl;
    }
    if ($opened_helper[$#scopestack]) {
        ehboth "end $name\.Helper;\n\n";
        close $hsfh;
        close $hbfh;
    }
    pop @opened_helper;
    pop @scopestack;
    if (@scopestack) {
        $psfh = $proxy_spec_file_handle[$#scopestack];
        $pbfh = $proxy_body_file_handle[$#scopestack];
        $osfh = $poa_spec_file_handle[$#scopestack];
        $obfh = $poa_body_file_handle[$#scopestack];
        if ($gen_ispec[$#scopestack]) {
            $isfh = $impl_spec_file_handle[$#scopestack];
        }
        if ($gen_ibody[$#scopestack]) {
            $ibfh = $impl_body_file_handle[$#scopestack];
        }
        if ($opened_helper[$#scopestack]) {
            $hsfh = $hlp_spec_file_handle[$#scopestack];
            $hbfh = $hlp_body_file_handle[$#scopestack];
        }
    }
}


sub print_spec_interface {
    my $iface = shift;
    my $ancestor = shift;
    # specindent "package $iface is\n\n";
    ppspec "type Ref is new ";
    pospec "type Object is abstract new ";
    if (@{$ancestor}) {   # multi-inheritance TBD
        my $first_ancestor = $$ancestor[0];
        my $faname = ${$first_ancestor}[$NAME];
        epspec($faname . ".Ref");
        eospec "POA_$faname\.Object";
    } else {
        epspec "CORBA.Object.Ref";
        eospec "PortableServer.ServantBase.Object\n";
    }
    pospec "                             with null record;\n";
    pospec "type Object_Access is access all Object'Class;\n\n";
    pospec("procedure Init (Self : Object_Access);\n\n");

    epspec " with null record;\n\n";
    $iface =~ s/\./::/g;
    ppspec "Typename : constant CORBA.String\n";
    ppspec "         := CORBA.To_Unbounded_String (\"$iface\");\n\n";
    ppspec "-- Narrow/Widen functions\n";
    ppspec "--\n";
    ppspec "function To_Ref (From: in CORBA.Object.Ref'CLASS) return Ref;\n";
    ppspec "function To_Ref (From: in CORBA.Any) return Ref;\n";
    ppspec "\n";
    ppspec "-- function Get_Interface return CORBA.InterfaceDef.Ref;\n";
    ppspec "-- function Get_Implementation return CORBA.ImplementationDef.Ref;\n";
    ppspec "\n";
}

sub print_body_interface {
    my $iface = shift;
    # ppbody "package body $iface is\n\n";
    # $body_ilvl[$#body_ilvl]++;
    ppbody "function To_Ref (From: in CORBA.Any) return Ref is\n";
    ppbody "  Temp: Ref;\n";
    ppbody "begin\n";
    ppbody "      -- Not yet implemented\n";
    ppbody "      --  \n";
    ppbody "  return Temp;\n";
    ppbody "end To_Ref;\n";
    ppbody "\n\n";
    ppbody "function To_Ref (From: in CORBA.Object.Ref'CLASS) return Ref is\n";
    ppbody "begin\n";
    ppbody "  return Ref (From);\n";
    ppbody "end To_Ref;\n";
    ppbody "\n\n";
    # POA body
    pobody "package C_Map is new PortableServer.ServantBase.C_Map\n";
    $poa_ilvl[$#poa_ilvl] += $INDENT2;
    pobody "(Object, Object_Access);\n";
    $poa_ilvl[$#poa_ilvl] -= $INDENT2;
    pobody "\n";
    pobody("procedure Init (Self : Object_Access) is\n");
    $poa_ilvl[$#poa_ilvl]++;
    pobody "procedure C_Init (Servant : PortableServer.ServantBase.C_Servant_Access;\n";
    pobody "                  Env : access CORBA.Environment.Object);\n";
    $iface =~ s/\./_/g;
    pobody "pragma Import (C, C_Init, \"POA_$iface\__init\");\n";
    pobody "C_Servant : PortableServer.ServantBase.C_Servant_Access;\n";
    pobody "Env : aliased CORBA.Environment.Object;\n";
    $poa_ilvl[$#poa_ilvl]--;
    pobody "begin\n";
    $poa_ilvl[$#poa_ilvl]++;
    pobody "C_Servant := new PortableServer.ServantBase.C_Servant_Struct;\n";
    pobody "C_Servant.all := (ORB_Data => System.Null_Address,\n";
    pobody "                  VEPV_Address => vepv'address);\n";
    pobody "C_Init (C_Servant, Env'access);\n";
    pobody "if CORBA.Environment.Exception_Happened (Env) then\n";
    pobody "   raise Constraint_Error;\n";
    pobody "end if;\n";
    pobody "PortableServer.ServantBase.Set_C_Servant (Self, C_Servant);\n";
    pobody "C_Map.Insert (Self);\n";
    $poa_ilvl[$#poa_ilvl]--;
    pobody "end Init;\n\n";
}

sub print_ispec_interface {
    my $iface = shift;
    my $ancestor = 0;
    if (@_) {
        $ancestor = shift;
    }
    # pispec "package $iface\.Impl is\n\n";
    # $ispec_ilvl[$#ispec_ilvl]++;
    pispec "type Object is new ";
    if (@{$ancestor}) {   # multi-inheritance TBD
        my $first_ancestor = $$ancestor[0];
        eispec(${$first_ancestor}[$NAME] . ".Impl.Object");
    } else {
        eispec "POA_$iface\.Object";
    }
    eispec " with private;\n\n";
}

sub print_ibody_interface {
    my $iface = shift;
}

sub print_interface_prologues {
    my $ancestor = shift;
    my $adaname = join ".", @scopestack;
    print_pkg_decl $adaname;
    print_spec_interface($adaname, $ancestor);
    print_body_interface $adaname;
    print_ispec_interface($adaname, $ancestor);
    print_ibody_interface $adaname;
}


sub open_files {
    my $name = shift;
    my $type = shift;
    push @scopestack, $name;
    push @opened_helper, 0;
    my $basename = lc(join "-", @scopestack);
    my $specfile = $basename . ".ads";
    my $bodyfile = $basename . ".adb";
    $psfh = $proxy_spec_file_handle[$#scopestack];
    $pbfh = $proxy_body_file_handle[$#scopestack];
    open($psfh, ">$specfile") or die "cannot create file $specfile\n";
    open($pbfh, ">$bodyfile") or die "cannot create file $bodyfile\n";
    if ($type == $CORBA::IDLtree::INTERFACE) {
        my $ispecfile = $basename . "-impl.ads";
        my $ibodyfile = $basename . "-impl.adb";
        my $poaspecfile = "poa_" . $basename . ".ads";
        my $poabodyfile = "poa_" . $basename . ".adb";
        if (-e $ispecfile) {
            $gen_ispec[$#scopestack] = 0;
        } else {
            $isfh = $impl_spec_file_handle[$#scopestack];
            open($isfh, ">$ispecfile") or die "cannot create $ispecfile\n";
            $gen_ispec[$#scopestack] = 1;
        }
        if (-e $ibodyfile) {
            if ($gen_ispec[$#scopestack]) {
                print "$ispecfile does not exist, but $ibodyfile does\n";
                print "         => generating only $ispecfile\n";
            } elsif ($verbose) {
                print "not generating $basename implementation files ";
                print "because they already exist\n";
            }
            $gen_ibody[$#scopestack] = 0;
        } else {
            $ibfh = $impl_body_file_handle[$#scopestack];
            open($ibfh, ">$ibodyfile") or die "cannot create $ibodyfile\n";
            if (! $gen_ispec[$#scopestack]) {
                print "$ispecfile does exist, but $ibodyfile does not\n";
                print "         => generating only $ibodyfile\n";
            }
            $gen_ibody[$#scopestack] = 1;
        }
        $osfh = $poa_spec_file_handle[$#scopestack];
        open($osfh, ">$poaspecfile") or die "cannot create $poaspecfile\n";
        $obfh = $poa_body_file_handle[$#scopestack];
        open($obfh, ">$poabodyfile") or die "cannot create $poabodyfile\n";
    }
    my $adaname = join ".", @scopestack;
    if (exists $helpers{$adaname}) {
        my $helperspec = $basename . "-helper.ads";
        my $helperbody = $basename . "-helper.adb";
        $hsfh = $hlp_spec_file_handle[$#scopestack];
        $hbfh = $hlp_body_file_handle[$#scopestack];
        open($hsfh, ">$helperspec")
                or die "cannot create file $helperspec\n";
        open($hbfh, ">$helperbody")
                or die "cannot create file $helperbody\n";
        $opened_helper[$#scopestack] = 1;
        ehspec "with System, C_Strings, CORBA.C_Types;\n";
        if ($need_exceptions) {
            ehspec "with System.Address_To_Access_Conversions;\n";
        }
        if ($need_unbounded_seq) {
            ehspec "with CORBA.C_Types.Simple_Unbounded_Seq, " .
                        "CORBA.C_Types.Unbounded_Seq;\n";
        }
        if ($need_bounded_seq) {
            ehspec "with CORBA.C_Types.Simple_Bounded_Seq, " .
                        "CORBA.C_Types.Bounded_Seq;\n";
        }
        ehspec "\n";
        ehboth "package ";
        ehbody "body ";
        ehboth "$adaname\.Helper is\n\n";
    }
    print_pkg_prologues($adaname, $type == $CORBA::IDLtree::MODULE);
}


sub charlit {
    my $input = shift;
    my $outbufref = shift;
    my $pos = 0;
    if ($input !~ /^\\/) {
        $$outbufref = substr($input, $pos, 1);
        return 1;
    }
    my $ch = substr($input, ++$pos, 1);
    my $consumed = 2;
    my $output = "Character'Val ";
    if ($ch eq 'n') {
        $output .= '(10)';
    } elsif ($ch eq 't') {
        $output .= '(9)';
    } elsif ($ch eq 'v') {
        $output .= '(11)';
    } elsif ($ch eq 'b') {
        $output .= '(8)';
    } elsif ($ch eq 'r') {
        $output .= '(13)';
    } elsif ($ch eq 'f') {
        $output .= '(12)';
    } elsif ($ch eq 'a') {
        $output .= '(7)';
    } elsif ($ch eq 'x') {         # hex number
        my $tuple = substr($input, ++$pos, 2);
        if ($tuple !~ /[0-9a-f]{2}/i) {
            $output = $ch;
            print "unknown escape \\x$tuple in string\n";
        } else {
            $output .= "(16#" . $tuple . "#)";
            $consumed += 2;
        }
    } elsif ($ch eq '0' or $ch eq '1') {     # octal number
        my $triple = substr($input, $pos, 3);
        if ($triple !~ /[0-7]{3}/) {
            $output = $ch;
            print "unknown escape \\$triple in string\n";
        } else {
            $output .= "(8#" . $triple . "#)";
            $consumed += 2;
        }
    } else {
        $output = $ch;
        print("unknown escape \\$ch in string\n") if ($ch =~ /[0-9A-z]/);
    }
    $$outbufref = $output;
    $consumed;
}

sub cvt_expr {
    my $lref = shift;
    my $charlit_output;
    my $output = "";

    foreach $input (@$lref) {
# print "cvt input = $input\n";
        my $ch = substr($input, 0, 1);
        if ($ch eq '"') {
            my $need_endquote = 1;
            $output .= '"';
            my $i;
            for ($i = 1; $i < length($input) - 1; $i++) {
                my $consumed = charlit(substr($input, $i), \$charlit_output);
                $i += $consumed - 1;
                if ($consumed > 1) {
                    $output .= '" & ';
                }
                $output .= $charlit_output;
                if ($consumed > 1) {
                    if ($i >= length($input) - 2) {
                        $need_endquote = 0;
                    } else {
                        # We had an escape, and are not yet at the end, so
                        # need to reopen the string
                        $output .= ' & "';
                    }
                }
            }
            if ($need_endquote) {
                $output .= '"';
            }
        } elsif ($ch eq "'") {
            my $consumed = charlit(substr($input, 1), \$charlit_output);
            if ($consumed == 1) {
                $output .= " '" . $charlit_output . "'";
            } else {
                $output .= " " . $charlit_output;
            }
        } elsif ($ch =~ /\d/) {
            if ($ch eq '0') {                   # check for hex/octal
                my $nxt = substr($input, 1, 1);
                if ($nxt eq 'x') {                  # hex const
                    $output .= ' 16#' . substr($input, 2) . '#';
                    next;
                } elsif ($nxt =~ /[0-7]/) {         # octal const
                    $output .= ' 8#' . substr($input, 1) . '#';
                    next;
                }
            }
            $output .= ' ' . $input;
        } elsif ($ch eq '.') {
            $output .= '0' . $input;
        } elsif ($input =~ /;/) {
            print "where the hell does this semicolon come from ?!?\n";
        } else {
            $output .= ' ' . $input;
        }
    }
    $output;
}


sub isnode {
    return CORBA::IDLtree::isnode(shift);
}


sub prefix {
    # Package prefixing is only needed if the type referenced is
    # in a different scope.
    my $type = shift;
    if (! isnode $type) {
        die "prefix called on non-node ($type)\n";
    }
    my @node = @{$type};
    my $prefix = "";
    my @scope;
    while ((@scope = @{$node[$SCOPEREF]})) {
        $prefix = $scope[$NAME] . '.' . $prefix;
        @node = @scope;
    }
    my $curr_scope = join('.', @scopestack) . '.';
    if ($prefix eq $curr_scope) {
        $prefix = "";
    }
    $prefix;
}


sub helper_prefix {
    my $type = shift;
    if (! isnode $type) {
        die "helper_prefix called on non-node ($type)\n";
    }
    my @node = @{$type};
    my $prefix = "";
    my @scope;
    while ((@scope = @{$node[$SCOPEREF]})) {
        $prefix = $scope[$NAME] . '.' . $prefix;
        @node = @scope;
    }
    $prefix . "Helper";
}


sub c_var_type {
    my $type = shift;
    if ($type == $CORBA::IDLtree::BOOLEAN) {
        return "CORBA.Char";
    } elsif ($type == $CORBA::IDLtree::STRING) {
        return "C_Strings.Chars_Ptr";
    } elsif (is_objref $type) {
        return "System.Address";
    } elsif (! isnode($type) or ! is_complex($type)) {
        return mapped_type($type);  # return Ada type
    }
    my @node = @{$type};
    my $helper = helper_prefix($type);
    my $rv;
    if ($node[$TYPE] == $CORBA::IDLtree::STRUCT ||
        $node[$TYPE] == $CORBA::IDLtree::UNION) {
        $rv = $helper . ".C_" . $node[$NAME];
    } elsif ($node[$TYPE] == $CORBA::IDLtree::BOUNDED_STRING) {
        $rv = "C_Strings.Chars_Ptr";
    } elsif ($node[$TYPE] == $CORBA::IDLtree::SEQUENCE) {
        $rv = "CORBA.C_Types.C_Sequence";
    } elsif ($node[$TYPE] == $CORBA::IDLtree::TYPEDEF) {
        my @origtype_and_dim = @{$node[$SUBORDINATES]};
        if ($origtype_and_dim[1] && @{$origtype_and_dim[1]}) {
            $rv = $helper . ".C_" . $node[$NAME];
        } else {
            $rv = c_var_type($origtype_and_dim[0]);
        }
    } else {
        $rv = "<c_var_type UFO>";
    }
    $rv;
}


sub seq_pkgname {
    my $seqtype = shift;
    my $lang_c = 0;
    if (@_) {
        $lang_c = shift;
    }
    if (! isnode($seqtype) || $$seqtype[$TYPE] != $CORBA::IDLtree::SEQUENCE) {
        print "internal error: seq_pkgname called on non-sequence\n";
        return "";
    }
    my @node = @{$seqtype};
    my $bound = "";
    if ($node[$NAME]) {
        $bound = $node[$NAME] . '_';
    }
    my $elemtype = CORBA::IDLtree::typeof($node[$SUBORDINATES]);
    my $rv;
    if ($lang_c) {
        $rv = helper_prefix($seqtype) . ".C_Seq_$bound$elemtype";
    } else {
        $rv = prefix($seqtype) . "IDL_Sequence_$bound$elemtype";
    }
    $rv;
}


sub mapped_type {
    my $type_descr = shift;
    my $make_c_type = 0;
    if (@_) {
        $make_c_type = shift;
    }
    if ($make_c_type) {
        return c_var_type($type_descr);
    }
    my $rv;
    if (CORBA::IDLtree::is_elementary_type $type_descr) {
        if (isnode($type_descr) &&
            $$type_descr[$TYPE] == $CORBA::IDLtree::TYPEDEF) {
            return(prefix($type_descr) . $$type_descr[$NAME]);
        }
        $rv = "CORBA." . ucfirst($CORBA::IDLtree::predef_types[$type_descr]);
        if ($type_descr == $CORBA::IDLtree::OBJECT) {
            $rv .= ".Ref";
        }
        return $rv;
    }
    my @node = @{$type_descr};   # We are sure that it IS a node at this point
    if ($#node != 3) {
        $rv = "<INTERNAL ERROR: mapped_type called on non-node>";
    } elsif ($node[$TYPE] == $CORBA::IDLtree::SEQUENCE) {
        $rv = seq_pkgname($type_descr) . '.Sequence';
    } elsif ($node[$TYPE] == $CORBA::IDLtree::BOUNDED_STRING) {
        $rv = "CORBA.Bounded_String_$node[$NAME]\.Bounded_String";
    } else {
        $rv = prefix($type_descr) . $node[$NAME];
        if ($node[$TYPE] == $CORBA::IDLtree::INTERFACE) {
            if ($make_c_type) {
                $rv = "System.Address";
            } else {
                $rv .= ".Ref";
            }
        }
    }
    $rv;
}


sub check_sequence {
    my $type_descriptor = shift;
    if (! isnode($type_descriptor) or
        $$type_descriptor[$TYPE] != $CORBA::IDLtree::SEQUENCE) {
        return mapped_type($type_descriptor);
    }
    my @node = @{$type_descriptor};
    my $element_type = $node[$SUBORDINATES];
    if (isnode($element_type) &&
        $$element_type[$TYPE] == $CORBA::IDLtree::SEQUENCE) {
        check_sequence($element_type);
    }
    my $bound = $node[$NAME];
    my $eletypnam = mapped_type($element_type);
    my $boundtype = ($bound) ? "Bounded" : "Unbounded";
    # take care of the Proxy spec
    my $pkgname = seq_pkgname($type_descriptor);
    ppspec "package $pkgname is new CORBA.Sequences.$boundtype";
    epspec " ($eletypnam";
    epspec(", " . $bound) if ($bound);
    epspec ");\n\n";
    # take care of the Helper spec
    my $cplx = is_complex($element_type);
    my $celetypnam;
    $celetypnam = CORBA::IDLtree::typeof($element_type, $GEN_C_TYPE, 1);
    my $seq_hlppkg = seq_pkgname($type_descriptor, $GEN_C_TYPE);
    # Remove helper package prefix because we're there already.
    $seq_hlppkg =~ s/^.*\.//;
    my $allocfun = "${seq_hlppkg}_allocbuf";
    ehspec "   function $allocfun (Length : CORBA.Unsigned_Long)\n";
    ehspec "            return System.Address;\n";
    ehspec "   pragma Import (C, $allocfun,\n";
    ehspec "                  \"CORBA_sequence_${celetypnam}_allocbuf\");\n\n";
    my $simple = ($cplx) ? "" : "Simple_";
    ehspec "   package $seq_hlppkg is new CORBA.C_Types.";
    ehspec "$simple$boundtype\_Seq\n";
    ehspec "     ($eletypnam, ";
    if ($bound) {
        ehspec "$bound, ";
    }
    ehspec("$pkgname, $allocfun");
    if ($cplx) {
        my $c2ada;
        my $ada2c;
        if ($cplx == 1 || $cplx == 2) {
            $ada2c = "CORBA.C_Types.To_C";
            $c2ada = "CORBA.C_Types.To_Ada";
        } else {
            my $hlpprefix = helper_prefix($type_descriptor);
            $ada2c = "$hlpprefix\.To_C";
            $c2ada = "$hlpprefix\.To_Ada";
        }
        ehspec ",\n";
        $celetypnam = mapped_type($element_type, $GEN_C_TYPE);
        ehspec "      $celetypnam, $ada2c, $c2ada";
    }
    ehspec ");\n\n";
    $pkgname . ".Sequence";
}


sub mangled_name {
    my $orig_name = shift;
    my $count = 0;
    my @line;
    my $object_file = $idl_filename;
    $object_file =~ s/\.idl/.o/;
    if (not -e $object_file) {
        print("cannot fill Link_Name in pragma Import CPP because can't find "
              . $object_file . "\n");
        return($orig_name . "__FILL_THIS_IN_MANUALLY");
    }
    my $searchsym = $orig_name . "__.*R17CORBA_Environment";
    my $cmdline = "nm $object_file | grep \'$searchsym\'";
    open(NM, "$cmdline |") or die "mangled_name : can't run nm\n";
    while (<NM>) {
        chop;
        $line[$count++] = $_;
    }
    close NM;
    if (! $count) {
        print "mangled_name: nm finds no symbols in $object_file\n";
        return "$name\__FILL_THIS_IN_MANUALLY";
    }
    $count--;
    if ($count > 0) {
        print "mangled_name($orig_name): there were several matches.\n";
        print "Please select the number of the appropriate symbol:\n";
        my $i;
        for ($i = 0; $i <= $count; $i++) {
            print "\t$i => $line[$i]\n";
        }
        $count = <STDIN>;
     }
     my @nm_info = split /\s/, $line[$count];
     foreach (@nm_info) {
         if (/R17CORBA_Environment/) {
             return $_;
         }
     }
     print "mangled_name: couldn't find $searchsym in $object_file\n";
     "$name\__FILL_THIS_IN_MANUALLY";
}


sub pass_by_reference {
    my $type = shift;
    if (! isnode($type)) {
        return 0;
    }
    my @node = @{$type};
    my $rv;
    if ($node[$TYPE] == $CORBA::IDLtree::ENUM ||
        $node[$TYPE] == $CORBA::IDLtree::INTERFACE) {
        $rv = 0;
    } elsif ($node[$TYPE] == $CORBA::IDLtree::TYPEDEF) {
        my @origtype_and_dim = @{$node[$SUBORDINATES]};
        if ($origtype_and_dim[1] && @{$origtype_and_dim[1]}) {
            $rv = 1;
        } else {
            $rv = pass_by_reference($origtype_and_dim[0]);
        }
    } else {
        $rv = 1;
    }
    $rv;
}


sub c2adatype {
    my $target = shift;
    my $varname = shift;
    my $type = shift;
    my $mode = $CORBA::IDLtree::IN;
    if (@_) {
        $mode = shift;
    }
    my $cplx = is_complex($type, 1);
    my $rv;
    if ($cplx == 0) {
        my $adatype = mapped_type($type);
        my $ctype = mapped_type($type, $GEN_C_TYPE);
        if ($ctype ne $adatype) {
            return "<ERROR: c2adatype Ada /= C of $varname>";
        }
        $rv = $varname;
    } elsif ($cplx == 1 || $cplx == 2) {
        $rv = "CORBA.C_Types.To_Ada ($varname)";
    } elsif (is_objref $type) {
        return "CORBA.Object.Set_C_Ref ($target, $varname);";
    } else {
        my @node = @{$type};
        my $hlpprefix = helper_prefix($type);
        if ($node[$TYPE] == $CORBA::IDLtree::TYPEDEF) {
            my @origtype_and_dim = @{$node[$SUBORDINATES]};
            my $origtype = $origtype_and_dim[0];
            my $dim = $origtype_and_dim[1];
            if ($dim && @{$dim}) {
                if (is_complex $origtype) {
                    $rv = "$hlpprefix\.To_Ada ($varname)";
                } else {
                    $rv = $varname;
                }
            } else {
                return("declare\n         tmp : " .
                  mapped_type($origtype) .
                  ";\n      begin\n         " .
                  c2adatype("tmp", $varname, $origtype) .
                  "\n         $target := " . prefix($type) .
                  $node[$NAME] . " (tmp);\n      end;");
            }
        } elsif ($node[$TYPE] == $CORBA::IDLtree::SEQUENCE) {
            $rv = seq_pkgname($type, $GEN_C_TYPE) . ".Create ($varname)";
        } else {
            my $dotall = "";
            if ($varname !~ "^CTemp_") {
                if ($mode != $CORBA::IDLtree::IN) {
                    $dotall = ".all";
                }
            }
            $rv = "$hlpprefix\.To_Ada ($varname$dotall)";
        }
    }
    "$target := $rv;";
}

sub ada2ctype {
    my $varname = shift;
    my $type = shift;
    my $cplx = is_complex($type, 1);
    my $rv;
    if ($cplx == 0) {
        my $adatype = mapped_type($type);
        my $ctype = mapped_type($type, $GEN_C_TYPE);
        if ($ctype ne $adatype) {
            return "<ERROR: ada2ctype Ada /= C of $varname>";
        }
        $rv = $varname;
    } elsif ($cplx == 1 || $cplx == 2) {
        $rv = "CORBA.C_Types.To_C ($varname)";
    } elsif (is_objref $type) {
        $rv = "CORBA.Object.Get_C_Ref ($varname)";
    } else {
        my @node = @{$type};
        my $hlpprefix = helper_prefix($type);
        if ($node[$TYPE] == $CORBA::IDLtree::TYPEDEF) {
            my @origtype_and_dim = @{$node[$SUBORDINATES]};
            my $origtype = $origtype_and_dim[0];
            my $dim = $origtype_and_dim[1];
            if ($dim && @{$dim}) {
                if (is_complex $origtype) {
                    $rv = "$hlpprefix\.To_C ($varname)";
                } else {
                    $rv = $varname;
                }
            } elsif ($origtype == $CORBA::IDLtree::BOOLEAN) {
                $rv = "CORBA.C_Types.To_C (CORBA.Boolean ($varname))";
            } elsif ($origtype == $CORBA::IDLtree::STRING) {
                $rv = "CORBA.C_Types.To_C (CORBA.String ($varname))";
            } else {
                if ($$origtype[$TYPE] == $CORBA::IDLtree::SEQUENCE) {
                    $rv = seq_pkgname($origtype, $GEN_C_TYPE) . ".Create\n";
                    $rv .= "          (" . seq_pkgname($origtype) .
                           ".Sequence ($varname))";
                } else {
                    $rv = "$hlpprefix\.To_C ($varname)";
                }
            }
        } elsif ($node[$TYPE] == $CORBA::IDLtree::SEQUENCE) {
            $rv = seq_pkgname($type, $GEN_C_TYPE) . ".Create ($varname)";
        } else {
            $rv = "$hlpprefix\.To_C ($varname)";
        }
    }
    $rv;
}


sub make_c_interfacing_var {
    my $type = shift;
    my $name = shift;
    my $mode = shift;
    my $caller_already_added_return_param = 0;
    if (@_) {
        $caller_already_added_return_param = shift;
    }
    if ($mode != $CORBA::IDLtree::IN or is_complex $type) {
        ppbody "CTemp_$name : ";
        if ($mode != $CORBA::IDLtree::IN &&
            $type != $CORBA::IDLtree::BOOLEAN &&
            $type != $CORBA::IDLtree::STRING && ! is_objref($type)) {
           epbody "aliased ";
        }
        epbody(c_var_type($type) . ";\n");
    }
    if (! $caller_already_added_return_param and $name eq "Returns") {
        ppbody("Returns : " . mapped_type($type) . ";\n");
    }
}

sub c_var_name {
    my $type = shift;
    my $name = shift;
    my $mode = $CORBA::IDLtree::IN;
    if (@_) {
       $mode = shift;
    }
    if ($mode != $CORBA::IDLtree::IN or is_complex $type) {
        $name = "CTemp_" . $name;
    }
    $name;
}

sub ada_from_c_var {
    my $type = shift;
    my $name = shift;
    my $mode = shift;
    my $gen_adatemp_assignment = 0;
    if (@_) {
        $gen_adatemp_assignment = shift;
    }

    my ($a, $c);
    if ($mode == $CORBA::IDLtree::IN) {
        if (! $gen_adatemp_assignment || 
            (! pass_by_reference($type) && ! is_complex($type))) {
            return;
        }
    }
    if ($gen_adatemp_assignment) {
        $a = "AdaTemp_$name";
        $c = $name;
    } else {
        $a = $name;
        $c = "CTemp_$name";
    }
    my $stmt = c2adatype($a, $c, $type, $mode);
    if ($gen_adatemp_assignment) {
        pobody("$stmt\n") if ($stmt ne "$a := $c;");
    } else {
        ppbody "$stmt\n";
        if ($type == $CORBA::IDLtree::STRING) {
            ppbody "CORBA.C_Types.Free ($c);\n";  # typedefs: TBD
        }
    }
}

sub make_ada_interfacing_var {
    my $type = shift;
    my $name = shift;

    if (is_complex $type) {
        pobody("AdaTemp_$name : " . mapped_type($type) . ";\n");
    }
}

sub ada_var_name {
    my $type = shift;
    my $name = shift;

    if (is_complex $type) {
        $name = "AdaTemp_" . $name;
    }
    $name;
}

sub c_from_ada_var {
    my $type = shift;
    my $name = shift;
    my $mode = shift;
    my $gen_ctemp_assignment = 0;
    if (@_) {
        $gen_ctemp_assignment = shift;
    }

    my ($c, $a);
    if ($mode == $CORBA::IDLtree::IN) {
        if (! $gen_ctemp_assignment || ! is_complex($type)) {
            return;
        }
    }
    if ($gen_ctemp_assignment) {
        $c = "CTemp_$name";
        $a = $name;
    } else {
        $c = $name;
        if ($c ne "Returns" && $mode != $CORBA::IDLtree::IN) {
            $c .= ".all";
        }
        $a = "AdaTemp_$name";
    }
    my $converted = ada2ctype($a, $type);
    my $stmt = "$c := $converted;\n";
    if ($gen_ctemp_assignment) {
        ppbody $stmt;
    } elsif ($a ne $converted) {
        pobody $stmt;
    }
}


sub subprog_param_text {
    my $ptype = shift;
    my $pname = shift;
    my $pmode = shift;
    my $make_c_type = 0;
    if (@_) {
        $make_c_type = shift;
    }
    my $adatype = mapped_type($ptype, $make_c_type);
    my $adamode = ($pmode == $CORBA::IDLtree::IN ? 'in' :
                   $pmode == $CORBA::IDLtree::OUT ? 'out' : 'in out');
    if ($make_c_type) {
        if ($pmode != $CORBA::IDLtree::IN) {
            $adamode = 'access';
            # This MUST be access mode because it might be an IDL function
            # with inout or out parameters.
        }
    } elsif (is_objref $ptype) {
        $adatype .= "\'Class";
    }
    "$pname : $adamode $adatype";
}


sub is_complex {
    # Returns 0 if representation of type is same in C and Ada.
    # Returns 1 for boolean.
    # Returns 2 for string.
    # Returns 3 for all other types represented differently between C and Ada.
    # Returns 4 for typedef if the optional $return_code_for_typedef argument
    # is supplied and is true. If the optional $return_code_for_typedef arg
    # is not supplied or is false, then is_complex analyzes the typedef'ed
    # type for structural difference between the C and the Ada representation.
    my $type = shift;
    my $return_code_for_typedef = 0;
    if (@_) {
        $return_code_for_typedef = shift;
    }
    if ($type == $CORBA::IDLtree::BOOLEAN) {
        return 1;
    } elsif ($type == $CORBA::IDLtree::STRING) {
        return 2;
    } elsif ($type >= $CORBA::IDLtree::OCTET &&
        $type <= $CORBA::IDLtree::DOUBLE ||
        $type == $CORBA::IDLtree::ENUM ||
        $type == $CORBA::IDLtree::EXCEPTION) {
        return 0;
    } elsif (is_objref $type) {
        return 3;
    } elsif (isnode $type) {
        my @node = @{$type};
        if ($node[$TYPE] == $CORBA::IDLtree::ENUM) {
            return 0;
        } elsif ($node[$TYPE] == $CORBA::IDLtree::TYPEDEF) {
            if ($return_code_for_typedef) {
                return 4;
            }
            my @origtype_and_dim = @{$node[$SUBORDINATES]};
            return is_complex($origtype_and_dim[0]);
        } elsif ($node[$TYPE] != $CORBA::IDLtree::STRUCT &&
                 $node[$TYPE] != $CORBA::IDLtree::EXCEPTION) {
            return 3;
        }
        foreach $component (@{$node[$SUBORDINATES]}) {
            if (is_complex $$component[$TYPE]) {
                return 3;
            }
        }
        return 0;
    }
    3;
}


sub is_objref {
    my $type = shift;
    $type == $CORBA::IDLtree::OBJECT ||
     (isnode($type) &&
      $$type[$TYPE] == $CORBA::IDLtree::INTERFACE);
}


sub is_integer_type {
    my $type = shift;
    my $rv = 0;
    if ($type >= $CORBA::IDLtree::OCTET &&
        $type <= $CORBA::IDLtree::ULONG) {
        $rv = 1;
    } elsif (isnode($type) && $$type[$TYPE] == $CORBA::IDLtree::TYPEDEF) {
        my @origtype_and_dim = @{$$type[$SUBORDINATES]};
        $rv = is_integer_type($origtype_and_dim[0]);
    }
    $rv;
}


sub gen_ada_recursive {
    my $symroot = shift;

    if (! $symroot) {
        print "\ngen_ada: encountered empty elem (returning)\n";
        return;
    } elsif (not ref $symroot) {
        print "\ngen_ada: incoming symroot is $symroot (returning)\n";
        return;
    }
    if (not isnode $symroot) {
        foreach $elem (@{$symroot}) {
            gen_ada_recursive $elem;
        }
        return;
    }
    my @node = @{$symroot};
    my $name = $node[$NAME];
    my $type = $node[$TYPE];
    my $subord = $node[$SUBORDINATES];
    my @arg = @{$subord};

    if ($type == $CORBA::IDLtree::TYPEDEF) {
        my $typeref = $arg[0];
        my $dimref = $arg[1];
        my $adatype = check_sequence($typeref);
        my $cplx = is_complex $typeref;
        ppspec "type $name is ";
        if ($dimref and @{$dimref}) {
            epspec "array (";
            my $is_first_dim = 1;
            ehspec("   type C_$name is array (") if ($cplx);
            foreach $dim (@{$dimref}) {
                if ($dim !~ /\D/) {   # if the dim is a number
                    $dim--;           # then modify that number directly
                } else {
                    $dim .= " - 1" ;  # else leave it to the Ada compiler
                }
                if ($is_first_dim) {
                    $is_first_dim = 0;
                } else {
                    epspec ", ";
                    ehspec(", ") if ($cplx);
                }
                epspec("0.." . $dim);
                ehspec("0.." . $dim) if ($cplx);
            }
            epspec ") of ";
            ehspec(") of ") if ($cplx);
        } else {
            epspec "new ";
        }
        epspec "$adatype;\n";
        if ($dimref and @{$dimref}) {
            if ($cplx) {
                ehspec(c_var_type($typeref) . ";\n");
                ehspec "   pragma Convention (C, C_$name);\n\n";
                ehboth "   function To_C (From : $name) return C_$name";
                ehspec ";\n";
                ehspec "   pragma Inline (To_C);\n";
                ehbody " is\n";
                ehbody "      To : C_$name;\n";
                ehbody "   begin\n";
                ehbody "      for I in From'Range loop\n";
                ehbody("         To(I) := " .
                       ada2ctype("From(I)", $typeref) . ";\n");
                ehbody "      end loop;\n";
                ehbody "      return To;\n";
                ehbody "   end To_C;\n\n";
                ehboth "   function To_Ada (From : C_$name) return $name";
                ehspec ";\n";
                ehspec "   pragma Inline (To_Ada);\n\n";
                ehbody " is\n";
                ehbody "      To : $name;\n";
                ehbody "   begin\n";
                ehbody "      for I in From'Range loop\n";
                ehbody("         " .
                       c2adatype("To(I)", "From(I)", $typeref) .  "\n");
                ehbody "      end loop;\n";
                ehbody "      return To;\n";
                ehbody "   end To_Ada;\n\n";
            } else {
                ppspec "pragma Convention (C, $name);\n";
            }
        }
        epspec "\n";

    } elsif ($type == $CORBA::IDLtree::CONST) {
        my $adatype = mapped_type($arg[0]);
        my $expr = cvt_expr($arg[1]);
        ppspec "$name : constant ";
        if ($arg[0] == $CORBA::IDLtree::BOOLEAN) {
            epspec "$adatype := $expr";
        } elsif ($arg[0] == $CORBA::IDLtree::STRING) {
            epspec "$adatype := CORBA.To_Unbounded_String ($expr)";
        } elsif (isnode $arg[0]) {
            my @tn = @{$arg[0]};
            if ($tn[$TYPE] == $CORBA::IDLtree::BOUNDED_STRING) {
                epspec("$adatype := CORBA.Bounded_String_$tn[$NAME]" .
                       ".To_Bounded_String ($expr)");
            } elsif ($tn[$TYPE] == $CORBA::IDLtree::ENUM) {
               epspec "$adatype := $expr";
            } else {
               epspec "<Not_Yet_Implemented> := $expr";
            }
        } else {
            epspec ":= $expr";
        }
        epspec(";\n\n");

    } elsif ($type == $CORBA::IDLtree::ENUM) {
        ppspec("type $name is ");
        my $enum_literals = join(', ', @arg);
        if (length($name) + length($enum_literals) < 65) {
            epspec "($enum_literals);\n";
        } else {
            epspec "\n";
            my $first = 1;
            $spec_ilvl[$#spec_ilvl] += $INDENT2 - 1;
            foreach $lit (@arg) {
                if ($first) {
                    ppspec "  ($lit";
                    $spec_ilvl[$#spec_ilvl]++;
                    $first = 0;
                } else {
                    epspec ",\n";
                    ppspec $lit;
                }
            }
            epspec ");\n";
            $spec_ilvl[$#spec_ilvl] -= $INDENT2;
        }
        ppspec "pragma Convention (C, $name);\n\n";

    } elsif ($type == $CORBA::IDLtree::STRUCT ||
             $type == $CORBA::IDLtree::UNION ||
             $type == $CORBA::IDLtree::EXCEPTION) {
        my $is_union = ($type == $CORBA::IDLtree::UNION);
        my $need_help = is_complex(\@node);
        my @adatype = ();
        my $i = ($is_union) ? 1 : 0;
        # First, generate array and sequence type declarations if necessary
        for (; $i <= $#arg; $i++) {
            my @node = @{$arg[$i]};
            my $type = $node[$TYPE];
            next if ($type == $CORBA::IDLtree::CASE or
                     $type == $CORBA::IDLtree::DEFAULT);
            push @adatype, check_sequence($type);
            my $dimref = $node[$SUBORDINATES];
            if ($dimref and @{$dimref}) {
                my $name = $node[$NAME];
                ppspec("type " . $name . "_Array is array (");
                my $is_first_dim = 1;
                foreach $dim (@{$dimref}) {
                    if ($dim !~ /\D/) {   # if the dim is a number
                        $dim--;           # then modify that number directly
                    } else {
                        $dim .= " - 1" ;  # else leave it to the Ada compiler
                    }
                    if ($is_first_dim) {
                        $is_first_dim = 0;
                    } else {
                        epspec ", ";
                    }
                    epspec("0.." . $dim);
                }
                epspec(") of " . $adatype[$#adatype] . ";\n\n");
            }
        }
        # Now comes the actual struct/union/exception
        my $need_end_record = 1;
        my $typename = $name;
        if ($type == $CORBA::IDLtree::EXCEPTION) {
            ppspec "$name : exception;\n\n";
            $typename .= "_Members";
            ppspec "type $typename is new CORBA.IDL_Exception_Members ";
            if (@arg) {
                epspec "with record\n"
            } else {
                epspec "with null record;\n\n";
                $need_end_record = 0;
            }
        } else {
            ppspec "type $name ";
            if ($is_union) {
                my $adatype = mapped_type($arg[0]);
                epspec "(Switch : $adatype := $adatype\'First) ";
            }
            epspec "is record\n";
            ppspec("  case Switch is\n") if ($is_union);
        }
        if ($need_help && scalar(@arg)) {
            if ($is_union) {
                ehspec "   type Union_$typename";
                my $dtype = mapped_type($arg[0], $GEN_C_TYPE);
                ehspec " (Switch : $dtype := $dtype\'First)";
            } else {
                ehspec "   type C_$typename";
            }
            ehspec " is record\n";
            ehspec("     case Switch is\n") if ($is_union);
        }
        if ($need_end_record) {
            $spec_ilvl[$#spec_ilvl]++;
            my $had_case = 0;
            my $had_default = 0;
            my $n_cases = 0;
            for ($i = ($is_union) ? 1 : 0; $i <= $#arg; $i++) {
                my @node = @{$arg[$i]};
                my $name = $node[$NAME];
                my $type = $node[$TYPE];
                my $suboref = $node[$SUBORDINATES];
                if ($type == $CORBA::IDLtree::CASE or
                    $type == $CORBA::IDLtree::DEFAULT) {
                    if ($had_case) {
                        $spec_ilvl[$#spec_ilvl]--;
                    } else {
                        $had_case = 1;
                    }
                    if ($type == $CORBA::IDLtree::CASE) {
                        ppspec "when ";
                        ehspec "      when ";
                        my $first_case = 1;
                        foreach $case (@{$suboref}) {
                            if ($first_case) {
                                $first_case = 0;
                            } else {
                                epspec "| ";
                                ehspec "| ";
                            }
                            epspec "$case ";
                            ehspec "$case ";
                            $n_cases++;
                        }
                        epspec "=>\n";
                        ehspec "=>\n";
                    } else {
                        ppspec "when others =>\n";
                        ehspec "     when others =>\n";
                        $had_default = 1;
                    }
                    $spec_ilvl[$#spec_ilvl]++;
                } else {
                    ppspec($name . " : " . shift(@adatype) . ";\n");
                    if ($need_help) {
                        my $ctype = mapped_type($type, $GEN_C_TYPE);
                        ehspec "      $name : $ctype;\n";
                    }
                }
            }
            my $need_default = 0;
            if ($is_union) {
                if (! $had_default) {
                    if (is_integer_type $arg[0]) {
                        $need_default = 1;
                    } else {
                        my @enumnode = @{$arg[0]};
                        if ($n_cases < scalar(@{$enumnode[$SUBORDINATES]})) {
                            $need_default = 1;
                        }
                    }
                    if ($need_default) {
                        ppspec "when others =>\n";
                        ppspec "   null;\n";
                        ehspec "     when others =>\n";
                        ehspec "        null;\n";
                    }
                }
                specdedent "end case;\n";
                ehspec("      end case;\n");
            }
            specdedent "end record;\n";
            if ($need_help && scalar(@arg)) {
                epspec "\n";
                ehspec "   end record;\n";
                if ($is_union) {
                    ehspec "   pragma Unchecked_Union (Union_$typename);\n\n";
                    my $dtype = mapped_type($arg[0], $GEN_C_TYPE);
                    ehspec "   type C_$typename is record\n";
                    ehspec "      D : $dtype;\n";
                    ehspec "      U : Union_$typename;\n";
                    ehspec "   end record;\n";
                }
                ehspec "   pragma Convention (C, C_$typename);\n\n";
                ehboth "   function To_C (From : $typename) return C_$typename";
                ehspec ";\n";
                ehspec "   pragma Inline (To_C);\n";
                ehbody " is\n";
                ehbody "      To : C_$typename;\n";
                ehbody "   begin\n";
                if ($is_union) {
                    ehbody "      To.D := From.Switch;\n";
                    ehbody "      case From.Switch is\n";
                    for ($i = 1; $i <= $#arg; $i++) {
                        my @node = @{$arg[$i]};
                        my $name = $node[$NAME];
                        my $type = $node[$TYPE];
                        my $suboref = $node[$SUBORDINATES];
                        if ($type == $CORBA::IDLtree::CASE) {
                            # find the component type for these cases
                            my $j;
                            my $cnv;
                            for ($j = $i + 1; $j <= $#arg; $j++) {
                                @node = @{$arg[$j]};
                                $type = $node[$TYPE];
                                if ($type != $CORBA::IDLtree::CASE) {
                                    $cnv = ada2ctype
                                          ("From." . $node[$NAME], $type);
                                    last;
                                }
                            }
                            # Must generate separate assignment for each case
                            # because pragma Unchecked_Union disallows mention
                            # of the discriminant other than in an aggregate
                            # assignment.
                            foreach $case (@{$suboref}) {
                                ehbody "        when $case =>\n";
                                ehbody "          To.U := ($case, $cnv);\n";
                            }
                        } elsif ($type == $CORBA::IDLtree::DEFAULT) {
                            ehbody "        when others =>\n";
                            @node = @{$arg[$i + 1]};
                            my $cnv = ada2ctype("From." . $node[$NAME],
                                                $node[$TYPE]);
                            ehbody "          To.U := (From.Switch, $cnv);\n";
                            last;
                        }
                    }
                    if ($need_default) {
                        ehbody "        when others =>\n";
                        ehbody "           null;\n";
                    }
                    ehbody "      end case;\n";
                } else {
                    for ($i = 0; $i <= $#arg; $i++) {
                        my @node = @{$arg[$i]};
                        my $name = $node[$NAME];
                        my $cnv;
                        $cnv = ada2ctype("From.$name", $node[$TYPE]);
                        ehbody "      To.$name := $cnv;\n";
                    }
                }
                ehbody "      return To;\n";
                ehbody "   end To_C;\n\n";
                ehboth "   function To_Ada (From : C_$typename)";
                ehboth " return $typename";
                ehspec ";\n";
                ehspec "   pragma Inline (To_Ada);\n\n";
                ehbody " is\n";
                # if ($is_union) {
                #     ehbody("      Switch : " . mapped_type($arg[0]) .
                #            " := From.D;\n");
                # }
                ehbody "      To : $typename";
                if ($is_union) {
                    ehbody(" (From.D)");
                }
                ehbody ";\n";
                ehbody "   begin\n";
                if ($is_union) {
                    ehbody "      case From.D is\n";
                }
                for ($i = ($is_union) ? 1 : 0; $i <= $#arg; $i++) {
                    my @node = @{$arg[$i]};
                    my $name = $node[$NAME];
                    my $type = $node[$TYPE];
                    my $suboref = $node[$SUBORDINATES];
                    if ($type == $CORBA::IDLtree::CASE) {
                        ehbody "      when ";
                        my $first_case = 1;
                        my $firstcaseval;
                        foreach $case (@{$suboref}) {
                            if ($first_case) {
                                $first_case = 0;
                                $firstcaseval = $case;
                            } else {
                                ehbody "| ";
                            }
                            ehbody "$case ";
                        }
                        ehbody "=>\n";
                        # ehbody "         To := ($firstcaseval,\n";
                    } elsif ($type == $CORBA::IDLtree::DEFAULT) {
                        ehbody "      when others =>\n";
                    } else {
                        my $from = "From.";
                        if ($is_union) {
                            $from .= "U.";
                        }
                        ehbody("      " .
                          c2adatype("To.$name", "$from$name", $type) . "\n");
                    }
                }
                if ($need_default) {
                    ehbody "        when others =>\n";
                    ehbody "           null;\n";
                }
                ehbody("      end case;\n") if ($is_union);
                ehbody "      return To;\n";
                ehbody "   end To_Ada;\n\n";
                if ($type == $CORBA::IDLtree::EXCEPTION) {
                    ehspec "   package Cnv_C_$typename is new\n";
                    ehspec "      System.Address_To_Access_Conversions";
                    ehspec " (C_$typename);\n\n";
                }
            } else {
                ppspec "pragma Convention (C, $name);\n\n";
            }
        }
        if ($type == $CORBA::IDLtree::EXCEPTION) {
            ppbody "$name\_ExceptionObject : $typename;\n";
            my $cexname = "IDL:$pragprefix" . join('/', @scopestack) . "/$name";
            ppobody "$name\_ExceptionName : constant CORBA.String :=\n";
            ppobody "   CORBA.To_Unbounded_String (\"$cexname\");\n\n";
            # if (scalar(@arg) and not is_complex $symroot) {
                ppobody "package Cnv_$typename is new";
                epobody " System.Address_To_Access_Conversions\n";
                ppobody "           ($typename);\n\n";
            # }
            #################### proxy side Get_Members method
            ppboth("procedure Get_Members (From : in " .
                  "Ada.Exceptions.Exception_Occurrence;\n");
            ppboth "                       To : out $typename)";
            epspec ";\n\n";
            epbody " is\n";
            ppbody "begin\n";
            $body_ilvl[$#body_ilvl]++;
            ppbody "To := Cnv_$typename\.To_Pointer\n";
            $body_ilvl[$#body_ilvl] += 3;
            ppbody "(CORBA.Environment.Exception_Members_Address (From)).all;\n";
            $body_ilvl[$#body_ilvl] = 1;
            ppbody "end Get_Members;\n\n\n";
        }

    } elsif ($type == $CORBA::IDLtree::INCFILE) {
        $name =~ s/\.idl//i;
        ppspec "with $name;\n";

    } elsif ($type == $CORBA::IDLtree::PRAGMA_PREFIX) {
        $pragprefix = $name . '/';

    } elsif ($type == $CORBA::IDLtree::MODULE) {
        open_files($name, $type);
        my $adaname = join ".", @scopestack;
        print_pkg_decl $adaname;
        foreach $declaration (@arg) {
            gen_ada_recursive $declaration;
        }
        finish_pkg_decl $adaname;

    } elsif ($type == $CORBA::IDLtree::INTERFACE) {
        my $ancestor_ref = $arg[0];
        open_files($name, $type);
        my $adaname = join ".", @scopestack;
        print_interface_prologues($ancestor_ref);
        # For each attribute, a private member variable will be added
        # to the implementation object type.
        my @attributes = ();
        my @opnames = ();
        foreach $decl (@{$arg[1]}) {
            gen_ada_recursive $decl;
            next unless (isnode($decl));
            my $type = ${$decl}[$TYPE];
            my $name = ${$decl}[$NAME];
            if ($type == $CORBA::IDLtree::ATTRIBUTE) {
                push @attributes, $decl;
                push @opnames, "Get_" . $name;
                my $arg = ${$decl}[$SUBORDINATES];
                my $readonly = $$arg[0];
                push(@opnames, "Set_" . $name) unless $readonly;
            } elsif ($type == $CORBA::IDLtree::METHOD) {
                push @opnames, $name;
            }
        }
        if ($gen_ispec[$#scopestack]) {
            $ispec_ilvl[$#ispec_ilvl]--;
            pispec "private\n";
            $ispec_ilvl[$#ispec_ilvl]++;
            pispec "type Object is new ";
            if (@{$ancestor_ref}) {
                my $first_ancestor_node = ${$ancestor_ref}[0];
                eispec ${$first_ancestor_node}[$NAME];
                eispec ".Impl.Object";
                # multiple inheritance: TBD
            } else {
                eispec "POA_$adaname\.Object";
            }
            if (@attributes) {
                eispec " with record\n";
                $ispec_ilvl[$#ispec_ilvl]++;
                foreach $attr_ref (@attributes) {
                    my $name = ${$attr_ref}[$NAME];
                    my $subord = ${$attr_ref}[$SUBORDINATES];
                    my $typename = mapped_type(${$subord}[1]);
                    pispec "$name : $typename;";
                    eispec("   -- IDL: readonly") if (${$subord}[0]);
                    eispec "\n";
                }
                $ispec_ilvl[$#ispec_ilvl]--;
                pispec "end record;\n\n";
            } else {
                eispec " with null record;\n\n";
            }
        }
        # ORBit specific POA function The_Epv (required for inheritance)
        pospec "-- ORBit specific:\n";
        poboth "function The_Epv return System.Address";
        eospec ";\n";
        pospec "pragma Inline (The_Epv);\n\n";
        eobody " is\n";
        pobody "begin\n";
        pobody "   return epv'address;\n";
        pobody "end The_Epv;\n\n";
        # generate POA spec private part
        eospec $poaspecbuf;
        pospec("N_Methods : constant := " . scalar(@opnames) .";\n\n");
        pospec "epv : aliased array (0..N_Methods) of System.Address\n";
        pospec "    := (System.Null_Address,\n";
        my $i;
        for ($i = 0; $i <= $#opnames; $i++) {
            pospec("        C_" . $opnames[$i] . "\'address");
            if ($i < $#opnames) {
                eospec ",\n";
            } else {
                eospec ");\n\n";
            }
        }
        pospec "ServantBase_epv : array (0..2) of System.Address\n";
        pospec "   := (others => System.Null_Address); -- TBC\n\n";
        my $n_ancestors = scalar(@{$ancestor_ref});
        pospec "Inherited_Interfaces : constant := $n_ancestors;\n\n";
        pospec("vepv : array (0..1+Inherited_Interfaces) "
               . "of System.Address\n");
        pospec "   := (ServantBase_epv'address,\n";
        foreach $iface (@{$ancestor_ref}) {
            pospec("       POA_" . prefix($iface) . $$iface[$NAME] .
                   ".The_Epv,\n");
        }
        pospec "       epv'address);\n\n";
        finish_pkg_decl $adaname;

    } elsif ($type == $CORBA::IDLtree::ATTRIBUTE) {
        my $readonly = $arg[0];
        my $rettype = $arg[1];
        my $adatype = mapped_type($rettype);
        my $ctype = mapped_type($rettype, $GEN_C_TYPE);
        my $is_objtype = is_objref $rettype;

        # Get method
        if ($is_objtype) {
            pall "procedure ";
        } else {
            pall "function ";
        }
        eall    "Get_$name (Self : ";
        epboth  "in Ref";
        eiboth  "access Object";
        eospec  "access Object";
        if ($is_objtype) {
            eall "; Returns : out $adatype\'Class)";
        } else {
            eall ") return $adatype";
        }
        epispec ";\n";
        eospec  "\n";
        pospec  "         is abstract;\n";
        epibody " is\n";
        ######################## proxy body and POA file output
        $poaspecbuf_enabled = 2;
        $body_ilvl[$#body_ilvl]++;
        ppobody(sprintf "function C_Get_%-12s (This : in System.Address;\n",
                        $name);
        $body_ilvl[$#body_ilvl] += $INDENT2 + 1;
        $poa_ilvl[$#poa_ilvl] += $INDENT2 + 1;
        ppobody "Env : access CORBA.Environment.Object)\n";
        ppobody "return $ctype";
        ######################## proxy body, impl body, POA specbuf outputs
        epbody ";\n";
        eospecbuf ";\n";
        $poaspecbuf_enabled = 1;
        eobody " is\n";
        $body_ilvl[$#body_ilvl] -= $INDENT2 + 1;
        $poa_ilvl[$#poa_ilvl] -= $INDENT2 + 1;
        pospecbuf "pragma Convention (C, C_Get_$name);\n";
        if ($target_system == $TAO) {
            ppbody "pragma Import (CPP, C_Get_$name, \"$name\", Link_Name =>\n";
            ppbody("   \"" . mangled_name($name) . "\");\n");
            pospecbuf "pragma CPP_Virtual ($name);\n";
        } else {
            my $prefix = "";
            if (not $seen_global_scope) {
                $prefix = join("_", @scopestack) . "_";
            }
            my $imex = "(C, C_Get_$name, \"$prefix\_get_$name\");\n";
            ppbody "pragma Import $imex";
            $imex =~ s/ C_/ /;
            $imex =~ s/_get_/Get_/;
            ppspec "pragma Export $imex      -- avoid conflict with C name\n";
        }
        pospecbuf "\n";
        ppbody "Env : aliased CORBA.Environment.Object;\n";
        if (! $is_objtype) {
            make_c_interfacing_var($rettype, "Returns", $CORBA::IDLtree::OUT);
        }
        $body_ilvl[$#body_ilvl]--;
        ppibody "begin\n";
        $body_ilvl[$#body_ilvl]++;
        ppbody(c_var_name($rettype, "Returns", $CORBA::IDLtree::OUT) . " := ");
        epbody "C_Get_$name (CORBA.Object.Get_C_Ref (Self), Env'access);\n";
        ppbody "CORBA.Environment.Check_Exception (Env, \"C_Get_$name\");\n";
        ada_from_c_var($rettype, "Returns", $CORBA::IDLtree::OUT);
        ppbody("return Returns;\n") unless ($is_objtype);
        $body_ilvl[$#body_ilvl]--;
        pibody  "   return Self.$name;\n";
        ppibody "end Get_$name;\n\n";
        ######################## POA body output
        $poa_ilvl[$#poa_ilvl]++;
        pobody "Srvnt : Object_Access := C_Map.Find (This);\n";
        make_ada_interfacing_var($rettype, "Returns");
        pobody("Returns : " . mapped_type($rettype, $GEN_C_TYPE) . ";\n");
        $poa_ilvl[$#poa_ilvl]--;
        pobody  "begin\n";
        $poa_ilvl[$#poa_ilvl]++;
        pobody "if Srvnt = null then\n";
        pobody "   raise Constraint_Error;\n";
        pobody "end if;\n";
        pobody "begin\n";
        $poa_ilvl[$#poa_ilvl]++;
        pobody ada_var_name($rettype, "Returns");
        eobody " := Dispatch_Get_$name (Srvnt);\n";
        $poa_ilvl[$#poa_ilvl]--;
        pobody "exception\n";
        pobody "   when others =>\n";
        pobody "      CORBA.Environment.Set_System_Exception\n";
        pobody "                          (Env, CORBA.Environment.UNKNOWN);\n";
        pobody "end;\n";
        c_from_ada_var($rettype, "Returns", $CORBA::IDLtree::OUT);
        pobody "return Returns;\n";
        $poa_ilvl[$#poa_ilvl]--;
        pobody  "end C_Get_$name;\n\n";
        ######################## POA dispatch method output
        $poaspecbuf_enabled = 2;
        if ($is_objtype) {
            pobody "procedure ";
        } else {
            pobody "function ";
        }
        eobody "Dispatch_Get_$name (Self : Object_Access";
        if ($is_objtype) {
            eobody "; Returns : out $adatype\'Class)";
        } else {
            eobody ") return $adatype";
        }
        $poaspecbuf_enabled = 1;
        eospecbuf ";\n\n";
        eobody " is\n";
        pobody "begin\n";
        $poa_ilvl[$#poa_ilvl]++;
        if ($is_objtype) {
            pobody "";
        } else {
            pobody "return ";
        }
        eobody "Get_$name (Self";
        if ($is_objtype) {
            eobody ", Returns";
        }
        eobody ");\n";
        $poa_ilvl[$#poa_ilvl]--;
        pobody "end Dispatch_Get_$name;\n\n";
        $poaspecbuf_enabled = 0;
        # end of Get method
        if ($readonly) {
            epispec "\n";
            eospec "\n";
            return;
        }

        # Set method
        pall    "procedure Set_$name (Self : ";
        epboth   "in Ref";
        eiboth  "access Object";
        eospec  "access Object";
        eall    "; To : $adatype";
        eall("\'Class") if ($is_objtype);
        eall    ")";
        epispec ";\n\n";
        eospec  "\n";
        eospec  "            is abstract;\n\n";
        epibody " is\n";
        ######################## proxy body and POA file output
        $poaspecbuf_enabled = 2;
        $body_ilvl[$#body_ilvl]++;
        ppobody(sprintf "procedure C_Set_%-12s (This : in System.Address;\n",
                        $name);
        $body_ilvl[$#body_ilvl] += $INDENT2 + 1;
        $poa_ilvl[$#poa_ilvl] += $INDENT2 + 1;
        ppobody subprog_param_text($rettype, "To", $CORBA::IDLtree::IN,
                                   $GEN_C_TYPE);
        epobody ";\n";
        ppobody "Env : access CORBA.Environment.Object)";
        eospecbuf ";\n";
        epbody ";\n";
        $poaspecbuf_enabled = 1;
        eobody " is\n";
        $body_ilvl[$#body_ilvl] -= $INDENT2 + 1;
        $poa_ilvl[$#poa_ilvl] -= $INDENT2 + 1;
        pospecbuf "pragma Convention (C, C_Set_$name);\n";
        if ($target_system == $TAO) {
            ppbody "pragma Import (CPP, C_Set_$name, \"$name\", Link_Name =>\n";
            ppbody('   "' . mangled_name($name) . "\");\n");
            pospecbuf "pragma CPP_Virtual ($name);\n";
        } else {
            my $prefix = "";
            if (not $seen_global_scope) {
                $prefix = join("_", @scopestack) . "_";
            }
            my $imex = "(C, C_Set_$name, \"$prefix\_set_$name\");\n";
            ppbody "pragma Import $imex";
            $imex =~ s/ C_/ /;
            $imex =~ s/_set_/Set_/;
            ppspec "pragma Export $imex      -- avoid conflict with C\n";
        }
        pospecbuf "\n";
        ppbody "Env : aliased CORBA.Environment.Object;\n";
        make_c_interfacing_var($rettype, "To", CORBA::IDLtree::IN);
        $body_ilvl[$#body_ilvl]--;
        ppibody "begin\n";
        $body_ilvl[$#body_ilvl]++;
        c_from_ada_var($rettype, "To", $CORBA::IDLtree::IN, 1);
        ppbody "C_Set_$name (CORBA.Object.Get_C_Ref (Self),\n";
        $body_ilvl[$#body_ilvl] += $INDENT2;
        ppbody c_var_name($rettype, "To", $CORBA::IDLtree::IN);
        if (pass_by_reference $rettype) {
            epbody "'access";
        }
        epbody ", Env'access);\n";
        $body_ilvl[$#body_ilvl] -= $INDENT2;
        ppbody "CORBA.Environment.Check_Exception (Env, \"C_Set_$name\");\n";
        ada_from_c_var($rettype, "To", $CORBA::IDLtree::IN);
        $body_ilvl[$#body_ilvl]--;
        ######################## impl body output
        pibody  "   Self.$name := To;\n";
        ppibody "end Set_$name;\n\n";
        ######################## POA body output
        $poa_ilvl[$#poa_ilvl]++;
        pobody "Srvnt : Object_Access := C_Map.Find (This);\n";
        make_ada_interfacing_var($rettype, "To");
        $poa_ilvl[$#poa_ilvl]--;
        pobody  "begin\n";
        $poa_ilvl[$#poa_ilvl]++;
        pobody "if Srvnt = null then\n";
        pobody "   raise Constraint_Error;\n";
        pobody "end if;\n";
        ada_from_c_var($rettype, "To", $CORBA::IDLtree::IN, 1);
        pobody "begin\n";
        $poa_ilvl[$#poa_ilvl]++;
        pobody "Dispatch_Set_$name (Srvnt, ";
        eobody(ada_var_name($rettype, "To") . ");\n");
        $poa_ilvl[$#poa_ilvl]--;
        pobody "exception\n";
        pobody "   when others =>\n";
        pobody "      CORBA.Environment.Set_System_Exception\n";
        pobody "                          (Env, CORBA.Environment.UNKNOWN);\n";
        pobody "end;\n";
        $poa_ilvl[$#poa_ilvl]--;
        pobody  "end C_Set_$name;\n\n";
        ######################## POA dispatch method output
        $poaspecbuf_enabled = 2;
        pobody "procedure Dispatch_Set_$name (Self : Object_Access";
        eobody "; To : $adatype";
        eobody("\'Class") if ($is_objtype);
        eobody ")";
        $poaspecbuf_enabled = 1;
        eospecbuf ";\n\n";
        eobody " is\n";
        pobody "begin\n";
        $poa_ilvl[$#poa_ilvl]++;
        pobody "Set_$name (Self, To);\n";
        $poa_ilvl[$#poa_ilvl]--;
        pobody "end Dispatch_Set_$name;\n\n";
        $poaspecbuf_enabled = 0;

    } elsif ($type == $CORBA::IDLtree::METHOD) {
        # Exception method
        my @exc_list = @{pop @arg};  # last element in arg is exception list
        if (@exc_list) {
            ppbody "procedure Raise_$name\_Exception";
            epbody " (Env : in CORBA.Environment.Object) is\n";
            ppbody "   use type CORBA.Exception_Type;\n";
            ppbody "   use type CORBA.String;\n";
            ppbody "   package SSE renames System.Storage_Elements;\n";
            ppbody "   Id : CORBA.String;\n";
            ppbody "begin\n";
            $body_ilvl[$#body_ilvl]++;
            ppbody "if CORBA.Environment.Get_Exception_Type (Env) /=";
            epbody " CORBA.User_Exception then\n";
            ppbody "   return;\n";
            ppbody "end if;\n";
            ppbody "Id := CORBA.Environment.Exception_Id (Env);\n";
            foreach $exref (@exc_list) {
                my @exnode = @{$exref};
                my $exname = $exnode[$NAME];
                ppbody "if Id = $exname\_ExceptionName then\n";
                $body_ilvl[$#body_ilvl]++;
                my @components = @{$exnode[$SUBORDINATES]};
                if (@components) {
                    my $lhs = "CORBA.Environment.Exception_Value (Env)";
                    my $cplx = is_complex $exref;
                    if ($cplx) {
                        my $hlp = helper_prefix($exref);
                        $lhs = "$hlp\.To_Ada\n         "
                               . " ($hlp\.Cnv_C_$exname\_Members.To_Pointer\n"
                               . "              ($lhs).all)";
                    } else {
                        $lhs = "Cnv_$exname\_Members.To_Pointer ($lhs).all";
                    }
                    ppbody "$exname\_ExceptionObject := $lhs;\n";
                }
                ppbody "CORBA.Environment.Raise_Exception\n";
                ppbody "   ($exname\'Identity,";
                epbody " $exname\_ExceptionObject\'Address);\n";
                $body_ilvl[$#body_ilvl]--;
                ppbody "end if;\n";
            }
            ppbody "raise CORBA.Unknown;\n";
            $body_ilvl[$#body_ilvl]--;
            ppbody "end Raise_$name\_Exception;\n\n";
        }
        # The Actual Method
        my $rettype = shift @arg;
        if ($rettype == $CORBA::IDLtree::ONEWAY) {
            ppispec "-- oneway\n";
            $rettype = $CORBA::IDLtree::VOID;
        }
        my $add_return_param = 0;
        if ($rettype == $CORBA::IDLtree::VOID) {
            pall "procedure ";
        } else {
            if (is_objref $rettype) {
                $add_return_param = $rettype;
                $rettype = $CORBA::IDLtree::VOID;
            } else {
                foreach $pnode (@arg) {
                    my $pmode = $$pnode[$MODE];
                    if ($pmode != $CORBA::IDLtree::IN) {
                        $add_return_param = $rettype;
                        $rettype = $CORBA::IDLtree::VOID;
                        last;
                    }
                }
            }
            if ($add_return_param) {
                pall "procedure ";
            } else {
                pall "function  ";
            }
        }
        eall sprintf("%-12s (Self : ", $name);
        epboth "in Ref";
        eiboth "access Object";
        eospec "access Object";
        $poa_ilvl[$#poa_ilvl] += $INDENT2;
        if ($#arg >= 0 || $add_return_param) {
            $spec_ilvl[$#spec_ilvl] += $INDENT2;
            $body_ilvl[$#body_ilvl] += $INDENT2;
            if ($gen_ispec[$#scopestack]) {
                $ispec_ilvl[$#ispec_ilvl] += $INDENT2;
            }
            if ($gen_ibody[$#scopestack]) {
                $ibody_ilvl[$#ibody_ilvl] += $INDENT2;
            }
            my $i;
            for ($i = 0; $i <= $#arg; $i++) {
                my @pn = @{$arg[$i]};
                eall ";\n";
                pall subprog_param_text($pn[$TYPE], $pn[$NAME], $pn[$MODE]);
            }
            if ($add_return_param) {
                eall(";\n");
                pall("Returns : out " . mapped_type($add_return_param));
                eall("\'Class") if (is_objref $add_return_param);
            }
            $spec_ilvl[$#spec_ilvl] -= $INDENT2;
            $body_ilvl[$#body_ilvl] -= $INDENT2;
            if ($gen_ispec[$#scopestack]) {
                $ispec_ilvl[$#ispec_ilvl] -= $INDENT2;
            }
            if ($gen_ibody[$#scopestack]) {
                $ibody_ilvl[$#ibody_ilvl] -= $INDENT2;
            }
        }
        eall ")";
        if ($rettype != $CORBA::IDLtree::VOID) {
            eall "\n";
            pall("                    return " . mapped_type($rettype));
        }
        epispec  ";\n";
        if (@exc_list) {
            ppispec "-- raises (";
            foreach $exc (@exc_list) {
                epispec(${$exc}[$NAME] . " ");
            }
            epispec ")\n";
        }
        epispec "\n";
        epibody " is\n";
        eospec " is abstract;\n\n";
        $poa_ilvl[$#poa_ilvl] -= $INDENT2;

        ######################## Proxy body, POA specbuf, POA body outputs
        $poaspecbuf_enabled = 2;
        $body_ilvl[$#body_ilvl]++;
        if ($add_return_param) {     # restore original rettype if necessary
            $rettype = $add_return_param;
        }
        if ($rettype == $CORBA::IDLtree::VOID) {
            ppobody "procedure ";
        } else {
            ppobody "function  ";
        }
        epobody(sprintf "C_%-12s (This : in System.Address;\n", $name);
        $body_ilvl[$#body_ilvl] += $INDENT2 + 1;
        $poa_ilvl[$#poa_ilvl] += $INDENT2 + 1;
        my $i;
        if (@arg) {
            for ($i = 0; $i <= $#arg; $i++) {
                my @pnode = @{$arg[$i]};
                ppobody subprog_param_text($pnode[$TYPE], $pnode[$NAME],
                                           $pnode[$MODE], $GEN_C_TYPE);
                epobody ";\n";
            }
        }
        ppobody "Env : access CORBA.Environment.Object)";
        if ($rettype != $CORBA::IDLtree::VOID) {
            epobody "\n";
            ppobody("return " .  mapped_type($rettype, $GEN_C_TYPE));
        }
        epbody ";\n";
        $poaspecbuf_enabled = 1;
        eospecbuf ";\n";
        eobody " is\n";
        $body_ilvl[$#body_ilvl] -= $INDENT2 + 1;
        $poa_ilvl[$#poa_ilvl] -= $INDENT2 + 1;
        if ($target_system == $TAO) {
            ppbody "pragma Import (CPP, C_$name, \"$name\", Link_Name =>\n";
            ppbody('  "' . mangled_name($name) . "\");\n");
            pospecbuf "pragma CPP_Virtual ($name);\n\n";
        } else {
            my $prefix = "";
            if (not $seen_global_scope) {
                $prefix = join("_", @scopestack) . "_";
            }
            ppbody "pragma Import (C, C_$name, \"$prefix$name\");\n";
            pospecbuf "pragma Convention (C, C_$name);\n\n";
        }
        ######################## Proxy body-only output
        for ($i = 0; $i <= $#arg; $i++) {
            my @pn = @{$arg[$i]};
            make_c_interfacing_var($pn[$TYPE], $pn[$NAME], $pn[$MODE]);
        }
        ppbody "Env : aliased CORBA.Environment.Object;\n";
        if ($rettype != $CORBA::IDLtree::VOID) {
            make_c_interfacing_var($rettype, "Returns", $CORBA::IDLtree::OUT,
                                   $add_return_param);
        }
        $body_ilvl[$#body_ilvl]--;
        ppbody "begin\n";
        $body_ilvl[$#body_ilvl]++;
        for ($i = 0; $i <= $#arg; $i++) {
            my @pn = @{$arg[$i]};
            c_from_ada_var($pn[$TYPE], $pn[$NAME], $pn[$MODE], 1);
        }
        ppbody "";
        if ($rettype != $CORBA::IDLtree::VOID) {
            epbody(c_var_name($rettype, "Returns", $CORBA::IDLtree::OUT) .
                   " := ");
        }
        epbody "C_$name (CORBA.Object.Get_C_Ref (Self),\n";
        $body_ilvl[$#body_ilvl] += $INDENT2 - 1;
        if ($#arg >= 0) {
            for ($i = 0; $i <= $#arg; $i++) {
                my $pnode = $arg[$i];
                my $ptype = $$pnode[$TYPE];
                my $pname = $$pnode[$NAME];
                ppbody(c_var_name($ptype, $pname, $$pnode[$MODE]));
                if ($$pnode[$MODE] != $CORBA::IDLtree::IN) {
                    epbody "'access";
                }
                epbody ",\n";
            }
        }
        ppbody "Env'access);\n";
        $body_ilvl[$#body_ilvl] -= $INDENT2 - 1;
        ppbody "CORBA.Environment.Raise_System_Exception (Env);\n";
        if (@exc_list) {
            ppbody "Raise_$name\_Exception (Env);\n";
        }
        for ($i = 0; $i <= $#arg; $i++) {
            my @pnode = @{$arg[$i]};
            ada_from_c_var($pnode[$TYPE], $pnode[$NAME], $pnode[$MODE]);
        }
        if ($rettype != $CORBA::IDLtree::VOID) {
            ada_from_c_var($rettype, "Returns", $CORBA::IDLtree::OUT);
            if (! $add_return_param) {
                ppbody "return Returns;\n";
            }
        }
        $body_ilvl[$#body_ilvl]--;
        ######################## POA body-only output
        $poa_ilvl[$#poa_ilvl]++;
        for ($i = 0; $i <= $#arg; $i++) {
            my @pnode = @{$arg[$i]};
            make_ada_interfacing_var($pnode[$TYPE], $pnode[$NAME]);
        }
        if ($rettype != $CORBA::IDLtree::VOID) {
            make_ada_interfacing_var($rettype, "Returns");
            pobody("Returns : " . mapped_type($rettype, 1) . ";\n");
        }
        pobody "Srvnt : Object_Access := C_Map.Find (This);\n";
        $poa_ilvl[$#poa_ilvl]--;
        pobody "begin\n";
        $poa_ilvl[$#poa_ilvl]++;
        pobody "if Srvnt = null then\n";
        pobody "   raise Constraint_Error;\n";
        pobody "end if;\n";
        for ($i = 0; $i <= $#arg; $i++) {
            my @pn = @{$arg[$i]};
            ada_from_c_var($pn[$TYPE], $pn[$NAME], $pn[$MODE], 1);
        }
        pobody "begin\n";
        $poa_ilvl[$#poa_ilvl]++;
        pobody "";
        if (! $add_return_param and $rettype != $CORBA::IDLtree::VOID) {
            eobody(ada_var_name($rettype, "Returns") . " := ");
        }
        eobody "Dispatch_$name (Srvnt";
        $poa_ilvl[$#poa_ilvl] += $INDENT2 - 1;
        for ($i = 0; $i <= $#arg; $i++) {
            my @pnode = @{$arg[$i]};
            eobody(", " .  ada_var_name($pnode[$TYPE], $pnode[$NAME]));
            if ($pnode[$MODE] != $CORBA::IDLtree::IN &&
                ! is_complex($pnode[$TYPE])) {
                eobody ".all";
            }
        }
        if ($add_return_param) {
            eobody(", " . ada_var_name($rettype, "Returns"));
        }
        eobody ");\n";
        $poa_ilvl[$#poa_ilvl] -= $INDENT2 - 1;
        $poa_ilvl[$#poa_ilvl]--;
        pobody "exception\n";
        $poa_ilvl[$#poa_ilvl]++;
        foreach $exref (@exc_list) {
            my @exnode = @{$exref};
            my $exname = $exnode[$NAME];
            pobody "when E : $exname =>\n";
            $poa_ilvl[$#poa_ilvl]++;
            pobody "declare\n";
            $poa_ilvl[$#poa_ilvl]++;
            my $memtype = "$exname\_Members";
            pobody "AdaTemp_$exname : Cnv_$memtype\.Object_Pointer :=\n";
            pobody "   Cnv_$memtype\.To_Pointer\n";
            pobody "      (CORBA.Environment.Exception_Members_Address (E));\n";
            my $hlppkg = helper_prefix($exref);
            if (is_complex $exref) {
                pobody("CTemp_$exname : $hlppkg.Cnv_C_$memtype" .
                       ".Object_Pointer;\n");
                my $cprefix = $hlppkg;
                $cprefix =~ s/.Helper$//;
                $cprefix =~ s/\./_/g;
                pobody("function $exname\_Alloc return" .
                       " $hlppkg.Cnv_C_$memtype.Object_Pointer;\n");
                pobody("pragma Import (C, $exname\_Alloc," .
                       " \"$cprefix\_$exname\__alloc\");\n");
            }
            $poa_ilvl[$#poa_ilvl]--;
            pobody "begin\n";
            $poa_ilvl[$#poa_ilvl]++;
            my $cnv;
            if (is_complex $exref) {
                pobody "CTemp_$exname := $exname\_Alloc;\n";
                pobody("CTemp_$exname\.all := $hlppkg\.To_C " .
                       "(AdaTemp_$exname\.all);\n");
                $cnv = "$hlppkg.Cnv_C_$memtype\.To_Address (CTemp_$exname)";
            } else {
                $cnv = "Cnv_$memtype\.To_Address (AdaTemp_$exname)";
            }
            pobody "Env.Major := CORBA.User_Exception;\n";
            pobody "Env.Repo_Id := CORBA.C_Types.To_C ($exname";
            eobody                                     "_ExceptionName);\n";
            pobody "Env.Params := $cnv;\n";
            $poa_ilvl[$#poa_ilvl]--;
            pobody "end;\n\n";
            $poa_ilvl[$#poa_ilvl]--;
        }
        pobody "when others =>\n";
        pobody "   CORBA.Environment.Set_System_Exception\n";
        pobody "                        (Env, CORBA.Environment.UNKNOWN);\n";
        pobody "   -- To Be Refined!\n";
        $poa_ilvl[$#poa_ilvl]--;
        pobody "end;\n";
        for ($i = 0; $i <= $#arg; $i++) {
            my @pn = @{$arg[$i]};
            c_from_ada_var($pn[$TYPE], $pn[$NAME], $pn[$MODE]);
        }
        if ($rettype != $CORBA::IDLtree::VOID) {
            # $add_return_param : To Be Done
            c_from_ada_var($rettype, "Returns", $CORBA::IDLtree::OUT);
            pobody "return Returns;\n";
        }
        $poa_ilvl[$#poa_ilvl]--;
        pobody "end C_$name;\n\n";
        ######################## POA dispatch method output
        $poaspecbuf_enabled = 2;
        if ($add_return_param || $rettype == $CORBA::IDLtree::VOID) {
            pobody "procedure ";
        } else {
            pobody "function  ";
        }
        eobody "Dispatch_$name (Self : in Object_Access";
        $poa_ilvl[$#poa_ilvl] += $INDENT2 + 1;
        for ($i = 0; $i <= $#arg; $i++) {
            my @pn = @{$arg[$i]};
            eobody ";\n";
            pobody subprog_param_text($pn[$TYPE], $pn[$NAME], $pn[$MODE]);
        }
        if ($add_return_param) {
            eobody ";\n";
            pobody subprog_param_text($rettype, "Returns",
                                      $CORBA::IDLtree::OUT);
        }
        eobody ")";
        if (! $add_return_param && $rettype != $CORBA::IDLtree::VOID) {
            eobody "\n";
            pobody("return " .  mapped_type($rettype));
        }
        $poaspecbuf_enabled = 1;
        eospecbuf ";\n\n";
        eobody " is\n";
        $poa_ilvl[$#poa_ilvl] -= $INDENT2 + 1;
        pobody "begin\n";
        $poa_ilvl[$#poa_ilvl]++;
        if (! $add_return_param && $rettype != $CORBA::IDLtree::VOID) {
            pobody "return ";
        } else {
            pobody "";
        }
        eobody "$name (Self";
        $poa_ilvl[$#poa_ilvl] += $INDENT2 + 1;
        for ($i = 0; $i <= $#arg; $i++) {
            my @pnode = @{$arg[$i]};
            eobody(", " . $pnode[$NAME]);
        }
        if ($add_return_param) {
            eobody ", Returns";
        }
        eobody ");\n";
        $poa_ilvl[$#poa_ilvl] -= $INDENT2 + 2;
        pobody "end Dispatch_$name;\n\n";
        ######################## Impl body output
        pibody "begin\n";
        pibody  "  null;  -- dear user, please fill me in\n";
        ppibody "end $name;\n\n";
        $poaspecbuf_enabled = 0;
    } else {
        print "gen_ada: unknown type value $type\n";
    }
}


sub need_help {
    my $type = shift;
    if (not isnode $type) {
        return 0;
    }
    my @node = @{$type};
    my $rv = 0;
    if ($node[$TYPE] == $CORBA::IDLtree::SEQUENCE ||
        $node[$TYPE] == $CORBA::IDLtree::UNION) {
        $rv = 1;
    } elsif ($node[$TYPE] == $CORBA::IDLtree::STRUCT ||
             $node[$TYPE] == $CORBA::IDLtree::EXCEPTION) {
        $rv = is_complex($type);
    } elsif ($node[$TYPE] == $CORBA::IDLtree::TYPEDEF) {
        my @origtype_and_dim = @{$node[$SUBORDINATES]};
        $rv = need_help($origtype_and_dim[0]);
    }
    $rv;
}


sub get_scope {
    my $reference = shift;
    my $own_name = shift;
    my $scope;
#    if (exists $CORBA::IDLtree::Prefixes{$reference}) {
#        $scope = $CORBA::IDLtree::Prefixes{$reference};
#        $scope =~ s/\.\w+$//;
#    } else {
        $scope = $own_name;
#    }
    $scope;
}


sub check_helper {
    my $type = shift;
    my $scoperef = shift;
    my $current_scope = shift;
    if (need_help $type) {
        if (! $scoperef) {
            print "check_helper: strange need_help\n";
        }
        my $actual_scope = get_scope($scoperef, $current_scope);
        if (not exists $helpers{$actual_scope}) {
            $helpers{$actual_scope} = 1;
        }
    }
}


sub check_features_used {
    my $symroot = shift;
    my $scope = shift;
    my $inside_includefile = shift;
    if (! isnode($symroot)) {
        return;
    }
    my @node = @{$symroot};
    if ($node[$TYPE] == $CORBA::IDLtree::TYPEDEF) {
        my @origtype_and_dim = @{$node[$SUBORDINATES]};
        check_helper($origtype_and_dim[0], $node[$SUBORDINATES], $scope);
        check_features_used($origtype_and_dim[0], $scope, $inside_includefile);
    } elsif ($node[$TYPE] == $CORBA::IDLtree::STRUCT ||
             $node[$TYPE] == $CORBA::IDLtree::EXCEPTION) {
        if ($node[$TYPE] == $CORBA::IDLtree::EXCEPTION) {
            $need_exceptions = 1;
        }
        my @components = @{$node[$SUBORDINATES]};
        foreach $member (@components) {
            my $type = $$member[$TYPE];
            next if ($type == $CORBA::IDLtree::CASE ||
                     $type == $CORBA::IDLtree::DEFAULT);
            if (isnode $type) {
                my @n = @{$type};
                next if ($n[$TYPE] == $CORBA::IDLtree::INCFILE ||
                         $n[$TYPE] == $CORBA::IDLtree::MODULE ||
                         $n[$TYPE] == $CORBA::IDLtree::INTERFACE);
            }
            check_helper($type, $member, $scope);
            check_features_used ($type, $scope, $inside_includefile);
        }
    } elsif ($node[$TYPE] == $CORBA::IDLtree::UNION) {
        if (not exists $helpers{$scope}) {
            $helpers{$scope} = 1;
        }
    } elsif ($node[$TYPE] == $CORBA::IDLtree::SEQUENCE) {
        if ($node[$NAME]) {
            $need_bounded_seq = 1;
        } else {
            $need_unbounded_seq = 1;
        }
    } elsif ($node[$TYPE] == $CORBA::IDLtree::BOUNDED_STRING) {
        if (not exists $strbound{$node[$NAME]}) {
            my $bound = $node[$NAME];
            $strbound{$bound} = 1;
            my $filename = "corba-bounded_string_${bound}.ads";
            if (not -e $filename) {
                open(BSP, ">$filename") or die "cannot create $filename\n";
                print BSP "with CORBA.Bounded_Strings;\n\n";
                print BSP "package CORBA.Bounded_String_$bound is new";
                print BSP " CORBA.Bounded_Strings ($bound);\n\n";
                close BSP;
            }
        }
    } elsif ($node[$TYPE] == $CORBA::IDLtree::ATTRIBUTE) {
        my @roflag_and_type = @{$node[$SUBORDINATES]};
        check_helper($roflag_and_type[1], $node[$SUBORDINATES], $scope);
    } elsif ($node[$TYPE] == $CORBA::IDLtree::METHOD) {
        my @params = @{$node[$SUBORDINATES]};
        my $retvaltype = shift @params;
        check_helper($retvaltype, $node[$SUBORDINATES], $scope);
        foreach $param_ref (@params) {
            my @param = @{$param_ref};
            check_helper($param[$TYPE], $param_ref, $scope);
        }
    }
}


sub gen_ada {
    my $symtree = shift;
    @withlist = ();
    CORBA::IDLtree::traverse_tree($symtree, \&check_features_used);
    if (isnode $symtree) {
        my $type = ${$symtree}[$TYPE];
        my $name = ${$symtree}[$NAME];
        if ($type != $CORBA::IDLtree::MODULE and
            $type != $CORBA::IDLtree::INTERFACE) {
            print "$name: expecting MODULE or INTERFACE\n";
            return;
        }
        $did_file_prologues = 0;
        $poaspecbuf = "private\n\n";
        gen_ada_recursive $symtree;
        return;
    } elsif (not ref $symtree) {
        print "\ngen_ada: unsupported declaration $symtree (returning)\n";
        return;
    }

    foreach $noderef (@{$symtree}) {
        my $type = ${$noderef}[$TYPE];
        my $name = ${$noderef}[$NAME];
        my $suboref = ${$noderef}[$SUBORDINATES];
        $did_file_prologues = 0;
        $poaspecbuf = "private\n\n";

        if ($type == $CORBA::IDLtree::MODULE or
            $type == $CORBA::IDLtree::INTERFACE) {
            $global_scope_pkgname = "";
            gen_ada_recursive $noderef;

        } elsif ($type == $CORBA::IDLtree::INCFILE) {
            foreach $incnode (@{$suboref}) {
                if (! isnode($incnode) ||
                    ($$incnode[$TYPE] != $CORBA::IDLtree::INCFILE &&
                     $$incnode[$TYPE] != $CORBA::IDLtree::PRAGMA_PREFIX &&
                     $$incnode[$TYPE] != $CORBA::IDLtree::MODULE &&
                     $$incnode[$TYPE] != $CORBA::IDLtree::INTERFACE)) {
                    print("idl2ada restriction: cannot handle global-scope " .
                          "declaration in $name\n");
                } else {
                    push @withlist, $$incnode[$NAME];
                }
            }

        } elsif ($type == $CORBA::IDLtree::PRAGMA_PREFIX) {
            $pragprefix = $name . '/';

        } else {
            $global_scope_pkgname = $idl_filename;
            $global_scope_pkgname =~ s/\.idl$//;
            $global_scope_pkgname =~ s/\W/_/g;
            $global_scope_pkgname .= "_IDL_File";
            open_files($global_scope_pkgname, $CORBA::IDLtree::MODULE);
            ###############################################################
            # Remove myself from the scope stack so that modules/interfaces
            # defined in this file will not be children of ..._IDL_File.
            pop @scopestack;
            ###############################################################
            print_withlist;
            print_pkg_decl $global_scope_pkgname;
            $seen_global_scope = 1;
            gen_ada_recursive $noderef;
        }
    }
    if ($seen_global_scope) {
        finish_pkg_decl($global_scope_pkgname, 1);
    }
}

# The End.

