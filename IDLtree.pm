# CORBA/IDLtree.pm  IDL to symbol tree translator
# This module is distributed under the same terms as Perl itself.
# Copyright/primary author:  (C) 1998, Oliver M. Kellogg (kellogg@vs.dasa.de)
# 
# -----------------------------------------------------------------------------
# Ver. |   Date   | History
# -----+----------+------------------------------------------------------------
#  0.4  1999/04/20  Design change: added a back pointer to the enclosing
#                   scope to each node. The basic node now contains four
#                   elements: ($TYPE, $NAME, $SUBORDINATES, $SCOPE)
#                   Removed the %Prefixes hash that is thus obsolete.
#                   Replaced sub check_scope by sub curr_scope.
#  0.3  1999/04/11  Added a node for pragma prefix
#  0.2  1999/04/06  Minor cosmetic changes; tested subs traverse_tree 
#                   and traverse (for usage example, see idl2ada.pl)
#                   Preprocessor directives other than #include were
#                   actually mistreated (fixed so they are just ignored.)
#  0.1  1998/07/06  Corrected the first parameter to the check_scope call
#                   in process_members. 
#                   The two elements of @tuple in 'const' processing were
#                   the wrong way round, corrected that.
#                   Overhauled the explanation of the Symbol Tree which was
#                   buggy in itself.
#  0.0  1998/06/29  First public release, alpha stage
#                   Things known to need thought: forward declarations,
#                   generation of Typecode information. The symbol trees
#                   generated are pretty much nude'n'crude -- what you see in
#                   IDL is what you get in ST. What kind of decorative info do
#                   we need? Any ideas/discussion, please email to addr. above
#  -.-  Mar 1998    Start of development
#                   The first version of this worked as a simple one-pass
#                   text filter until I attempted implementing interface
#                   references. In order to generate a "Ref" for those (in
#                   Ada), it is necessary to distinguish them from other
#                   types (the Ada type name is different from the IDL type
#                   name.) This single requirement lead to the abandonment
#                   of the direct text-to-text transformation approach.
#                   Instead, IDL source text is first translated into a
#                   target language independent intermediate representation
#                   (the symbol tree), and the target language text is
#                   then generated from that intermediate representation.
# -----------------------------------------------------------------------------
#


package CORBA::IDLtree;
require 5.000;
require Exporter;
@ISA = (Exporter);
@EXPORT = ();
@EXPORT_OK = ();  # &Parse_File, &Dump_Symbols, and all the constants
                  # ($ENUM etc.) ;  potentially: %Prefixes


# -----------------------------------------------------------------------------
#
# Structure of the symbol tree:
#
# A "thing" in the symbol tree can be either a reference to a node, or a
# reference to an array of references to nodes.
#
# Each node is a four-element array with the elements
#   [0] => TYPE (MODULE|INTERFACE|STRUCT|UNION|ENUM|TYPEDEF|CHAR|...)
#   [1] => NAME
#   [2] => SUBORDINATES
#   [3] => SCOPEREF
#
# The TYPE element, instead of holding a type ID number (see the following
# list under SUBORDINATES), can also be a reference to the node defining the
# type. When the TYPE element can contain either a type ID or a reference to
# the defining node, we will call it a `type descriptor'.
# Which of the two alternatives is in effect can be determined via the
# isnode() function.
#
# The NAME element, unless specified otherwise, simply holds the name string
# of the respective IDL syntactic item.
#
# The SUBORDINATES element depends on the type ID:
#   MODULE or       Reference to an array of nodes (symbols) which are defined
#   INTERFACE       within the module or interface. In the case of INTERFACE,
#                   element [0] in this array will contain a reference to a
#                   further array which in turn contains references to the
#                   parent interface(s) if inheritance is used, or the null
#                   value if the current interface is not derived by
#                   inheritance.
#   STRUCT or       Reference to an array of node references representing the
#   UNION or        member components of the struct, union, or exception. In
#   EXCEPTION       case of UNION, element 0 contains a type descriptor for
#                   the discriminant type. Further, in case of a UNION, the
#                   TYPE of a node may also be CASE, or DEFAULT.
#                   In that case, the NAME is unused, and the SUBORDINATE
#                   contains a reference to a list of the case values for the
#                   following branch. The end of a branch is indicated by the
#                   next following node that has TYPE == CASE (or DEFAULT),
#                   or the end of the UNION. When TYPE is DEFAULT, both the
#                   NAME and the SUBORDINATE element of the node are unused.
#                   For normal struct/union/exception members, the SUBORDINATE
#                   node element contains a reference to a list of dimension
#                   numbers (or to an empty list if no dimensions were given
#                   for that component.)
#   ENUM            Reference to the array of enum value literals.
#                   Numeric representations are not yet supported.
#   TYPEDEF         Reference to a two-element array: element 0 contains a
#                   reference to the type descriptor of the original type;
#                   element 1 contains a reference to an array of dimension
#                   numbers, or the null value if no dimensions are given.
#   SEQUENCE        As a special case, the NAME element of a SEQUENCE node
#                   does not contain a name (as sequences are anonymous 
#                   types), but instead is used to hold the bound number.
#                   If the bound number is 0, then it is an unbounded
#                   sequence. The SUBORDINATES element contains the type
#                   descriptor of the base type of the sequence. This 
#                   descriptor could itself be a reference to a SEQUENCE
#                   defining node (that is, a nested sequence definition.)
#                   Bounded strings are treated as a special case of sequence.
#                   They are represented as references to a node that has
#                   BOUNDED_STRING as the type ID, the bound number in the
#                   NAME, and the SUBORDINATES element is unused.
#   CONST           Reference to a two-element array. Element 0 is a type
#                   descriptor of the const's type; element 1 is a reference
#                   to an array containing the RHS expression symbols.
#   ATTRIBUTE       Reference to a two-element array; element 0 is the read-
#                   only flag (0 for read/write attributes), element 1 is a
#                   type descriptor of the attribute's type.
#   METHOD          Reference to a variable length array; element 0 is a type
#                   descriptor for the return type. Elements 1 and following
#                   are references to parameter descriptor nodes with the
#                   following structure:
#                       elem. 0 => parameter type descriptor
#                       elem. 1 => parameter name
#                       elem. 2 => parameter mode (IN, OUT, or INOUT)
#                   The last element in the variable-length array is a
#                   reference to the "raises" list. This list contains
#                   references to the declaration nodes of exceptions raised,
#                   or is empty if there is no "raises" clause.
#   INCFILE         Reference to an array of nodes (symbols) which are defined
#                   within the include file. The Name element of this node
#                   contains the include file name.
#
# The SCOPEREF element is a reference back to the node of the module or 
# interface enclosing the current node. If the current node is already
# at the global scope level, then the SCOPEREF is 0. All nodes have this
# element except for the parameter nodes of methods and the component nodes
# of structs/unions/exceptions.
#

# Visible subroutines #########################################################

sub Parse_File;
    # Parse_File() is the universal entry point (called by the main program.)
    # It takes an IDL file name as the input parameter and parses that file,
    # constructing a symbol tree which is its return value. If there were
    # errors, then Parse_File returns 0.

sub Dump_Symbols;
    # Symbol tree dumper (for debugging etc.)


# Visible constants ###########################################################

# Meanings of symbol node index
$TYPE         = 0;
$NAME         = 1;
$SUBORDINATES = 2;
$MODE         = 2;    # alias of SUBORDINATES (for method parameter nodes)
$SCOPEREF     = 3;

# Parameter modes
$IN    = 1;
$OUT   = 2;
$INOUT = 3;

# Meanings of the $TYPE entry in the symbol node.
# If these codes are changed, then @predef_types must be changed accordingly.
$NONE           = 0;   # error/illegality value
$BOOLEAN        = 1;
$OCTET          = 2;
$CHAR           = 3;
$SHORT          = 4;
$LONG           = 5;
$USHORT         = 6;
$ULONG          = 7;
$FLOAT          = 8;
$DOUBLE         = 9;
$STRING         = 10;
$OBJECT         = 11;
$ANY            = 12;
$BOUNDED_STRING = 13;
$SEQUENCE       = 14;
$ENUM           = 15;
$TYPEDEF        = 16;
$STRUCT         = 17;
$UNION          = 18;
$CASE           = 19;
$DEFAULT        = 20;
$EXCEPTION      = 21;
$CONST          = 22;
$MODULE         = 23; 
$INTERFACE      = 24;
$ATTRIBUTE      = 25;
$ONEWAY         = 26;    # implies "void" as the return type
$VOID           = 27;
$METHOD         = 28;
$INCFILE        = 29;
$PRAGMA_PREFIX  = 30;
$NUMBER_OF_TYPES = 31;
# The @predef_types array must have the types in the same order as
# the numeric order of type identifying constants defined above.
@predef_types = qw/ none boolean octet char short long unsigned_short 
                    unsigned_long float double string Object any
                    string<> sequence enum typedef struct union case default
                    exception const module interface attribute oneway void
                    method incfile /;

# Language conventions
# Note that the IDLtree module is meant to be language independent.
# The only place these conventions are used is at sub typeof which
# returns the type name of a node in a language dependent notation.
# However, sub typeof is just an add-on commodity not required for
# IDLtree's basic functioning.
$LANG_IDL   = 0;
$LANG_C     = 1;
$LANG_CPP   = 2;
$LANG_ADA   = 3;
$LANG_JAVA  = 4;

# Visible subroutines #########################################################

sub is_elementary_type;
sub predef_type;
sub isnode;
    # Given a "thing", returns 1 if it is a reference to a node, 0 otherwise.
sub find_node;
sub typeof;
    # Given a type descriptor, returns the type as a string in IDL syntax.

# Internal subroutines (should not be visible)

sub getline;
sub check_name;
sub curr_scope;
sub parse_sequence;
sub parse_type;
sub parse_members;
sub error;
sub cvt_expr;
sub require_end_of_stmt;
sub idlsplit;

# Auxiliary (non-visible) global stuff ########################################

my @fh = qw/ IN0 IN1 IN2 IN3 IN4 IN5 IN6 IN7 IN8 IN9/;
    # Input file handles (constants)

my @prev_symroots = ();
    # Stack of the roots of previously constructed symtrees.
    # Used by find_node() for identifying symbols.
    # Elements are added to/removed from the front of this,
    # i.e. using unshift/shift (as opposed to push/pop.)

my @scopestack = ();
    # The scope stack. Elements in this stack are references to
    # MODULE or INTERFACE nodes.

my @infilename = ();    # infilename and line_number move in parallel.
my @line_number = ();
my $n_errors = 0;       # auxiliary to sub error
my $in_comment = 0;     # Auxiliary to &getline (multi-line comment processing)


sub getline {  # returns empty string for end-of-file or fatal error
    my $in = shift;
    my $line = "";
    while (<$in>) {
        $line_number[$#infilename]++;
        next if (/^\s*$/);       # empty
        next if (/^\s*\/\//);    # comment
        chop;
        if ($in_comment) {
            next unless (/\*\//);
            $in_comment = 0;     # end of multi-line comment
            s/^.*\*\///;
            next if (/^\s*$/);
        } elsif (/\/\*/) {       # start of multi-line comment
            if (/\*\//) {
                s/\/\*.*\*\///;
                next if (/^\s*$/);
            } else {
                $in_comment = 1;
                s/\/\*.*$//;
                next if (/^\s*$/);
            }
        }
        s/\/\/.*$//;             # discard trailing comment
        s/^\s+//;                # discard leading whitespace
        s/\s+$//;                # discard trailing whitespace
        $line .= $_;
        last if ($line =~ /^#/);   # preprocessor directive
        last if ($line =~ /[;"\{]$/);
    }
    $line;
}

sub idlsplit {
    my $str = shift;
    my $in_string = 0;
    my $in_lit = 0;
    my $in_space = 0;
    my $i;
    my @out = ();
    my $ondx = -1;
    for ($i = 0; $i < length($str); $i++) {
        my $ch = substr($str, $i, 1);
        if ($in_string) {
            $out[$ondx] .= $ch;
            if ($ch eq '"' and substr($str, $i-1, 1) ne "\\") {
                $in_string = 0;
                $ondx++;
            }
        } elsif ($ch eq '"') {
            $in_string = 1;
            $out[++$ondx] = $ch;
        } elsif ($ch eq "'") {
            my $endx = index $str, "'", $i + 2;
            if ($endx < $i + 2) {
                error "cannot find closing apostrophe of char literal";
                return @out;
            }
            $out[++$ondx] = substr($str, $i, $endx - $i + 1);
# print "idlsplit: $out[$ondx]\n";
            $i = $endx;
        } elsif ($ch =~ /[a-z_0-9\.]/i) {
            if (! $in_lit) {
                $in_lit = 1;
                $ondx++;
            }
            $out[$ondx] .= $ch;
        } elsif ($in_lit) {
            $in_lit = 0;
            if ($ch !~ /\s/) {
                $out[++$ondx] = $ch;
            }
        } elsif ($ch !~ /\s/) {
            $out[++$ondx] = $ch;
        }
    }
    # For simplification of further processing:
    # 1. Turn unsigned types into single keyword
    #      unsigned long  => unsigned_long
    #      unsigned short => unsigned_short
    # 2. Put scoped names back together, e.g. 'A' ':' ':' 'B' => 'A.B'
    #    The notation A.B is borrowed from Ada.
    for ($i = 0; $i < $#out - 1; $i++) {
        if ($out[$i] eq 'unsigned') {
            if ($out[$i+1] ne 'short' and $out[$i+1] ne 'long') {
                error "illegal unsigned type";
                last;
            }
            $out[$i] .= '_' . $out[$i + 1];
            splice @out, $i + 1, 1;
        } elsif ($out[$i] eq ':' and $out[$i+1] eq ':') {
            splice @out, $i, 2;
            if ($i > 0) {
                $out[$i - 1] .= '.' . $out[$i];
                splice @out, $i--, 1;
            }
        }
    }
    # Bounded strings are special-cased:
    # compress the notation "string<bound>" into one element
    for ($i = 0; $i < $#out - 1; $i++) {
        if ($out[$i] eq 'string' && $out[$i+1] eq '<' && $out[$i+3] eq '>') {
            if ($out[$i+2] =~ /\D/) {
                error "Non-numeric string bound is not yet implemented";
            }
            $out[$i] .= '<' . $out[$i + 2] . '>';
            splice @out, $i + 1, 3;
        }
    }
    @out;
}


sub is_elementary_type {
    my $tdesc = shift;  # argument: a type descriptor
    if (isnode($tdesc) && $$tdesc[$TYPE] == $TYPEDEF) {
        my @origtype_and_dim = @{$$tdesc[$SUBORDINATES]};
        return is_elementary_type($origtype_and_dim[0]);
    }
    # For our purposes, sequences, bounded strings, enums, structs and unions
    # do not count as predefined types. They are represented as a further
    # node, i.e. the argument to is_elementary_type is not a numeric constant,
    # but instead contains a reference to the defining node.
    # FIXME: Is $ANY really an elementary type? Is there any kind of
    #        decorative information that we should be generating for Any's?
    #        Generation of Typecode related info is not yet implemented and
    #        should be opened to discussion.
    ($tdesc >= $BOOLEAN && $tdesc <= $ANY);
}

sub predef_type {
    my $idltype = shift;
    my $i;
    for ($i = 1; $i <= $#predef_types; $i++) {
        if ($idltype eq $predef_types[$i]) {
            return $i;
        }
    }
    if (substr($idltype, 0, 6) eq "string" and
        substr($idltype, 6) =~ /^<(\d+)>$/) {
        my $string_bound = $1;
        my @typenode = ($BOUNDED_STRING, $string_bound, 0, curr_scope);
        return \@typenode;
    } else {
        $string_bound = 0;
    }
    0;
}


sub typeof {      # Returns the string of a "type descriptor"
    my $type = shift;
    my $lang = $LANG_IDL;    # language convention
    my $gen_fqn = 0;         # generate fully qualified name
    my $scope_separator = "::";
    if (@_) {
        $lang = shift;
        if (@_) {
            $gen_fqn = shift;
        }
        if ($lang == $LANG_C) {
            $scope_separator = '_';
        } elsif ($lang == $LANG_ADA) {
            $scope_separator = '.';
        }
    }
    my $rv = "";
    if ($type >= $BOOLEAN && $type <= $ANY) {
        $rv = $predef_types[$type];
        if ($lang != $LANG_IDL) {
            if ($lang == $LANG_ADA) {
                $rv = ucfirst $rv;
            }
            $rv = "CORBA" . $scope_separator . $rv;
        }
        return $rv;
    } elsif (! isnode($type)) {
        die "internal error: parameter to typeof is not a node\n";
    }
    my @node = @{$type};
    my $name = $node[$NAME];
    my $prefix = "";
    if ($gen_fqn) {
        my @scope;
        while ((@scope = @{$node[$SCOPEREF]})) {
            $prefix = $scope[$NAME] . $scope_separator . $prefix;
            @node = @scope;
        }
    }
    $rv = "$prefix$name";
    if ($node[$TYPE] == $BOUNDED_STRING) {
        if ($lang = $LANG_IDL) {
            $rv = 'string<' . $name . '>';
        } elsif ($lang = $LANG_ADA) {
            $rv = "CORBA.Bounded_String_$name\.Bounded_String";
        } else {
            $rv = "TO_BE_DONE";
        }
    } elsif ($node[$TYPE] == $SEQUENCE) {
        my $bound = $name;   # NAME holds the bound
        my $eltype = typeof($node[$SUBORDINATES], $lang);
        if ($lang = $LANG_IDL) {
            $rv = 'sequence<' . $eltype;
            if ($bound) {
                $rv .= ", $bound";
            }
            $rv .= '>';
        } elsif ($lang = $LANG_ADA) {
            if ($bound) {
                $bound .= '_';
            }
            $rv = "${prefix}IDL_SEQUENCE_${bound}${eltype}.Sequence";
        } else {
            $rv = "TO_BE_DONE";
        }
    }
    $rv;
}

sub check_name {
    my $name = shift;
    my $opt_msg = "";
    if (@_) {
        $opt_msg = shift;
    }
    if ($name =~ /[^a-z0-9_.]/i) {
        if ($opt_msg) {
            error("illegal " . $opt_msg);
        } else {
            error("illegal name");
        }
    }
}


sub curr_scope {
    ($#scopestack < 0 ? 0 : $scopestack[$#scopestack]);
}


sub parse_sequence {
    my ($argref, $symroot) = @_;
    if (shift @{$argref} ne '<') {
        error "expecting '<'";
        return 0;
    }
    my $nxtarg = shift @{$argref};
    my $type = predef_type $nxtarg;
    if (! $type) {
        $type = find_node($nxtarg, $symroot);
        if (! $type) {
            error "unknown sequence type";
            return 0;
        }
    } elsif ($type == $SEQUENCE) {
        $type = parse_sequence($argref, $symroot);
    }
    my $bound = 0;
    $nxtarg = shift @{$argref};
    if ($nxtarg eq ',') {
        $bound = shift @{$argref};
        if ($bound =~ /\D/) {
            error "Sorry, non-numeric sequence bound is not implemented";
            return 0;
        }
        $nxtarg = shift @{$argref};
    }
    if ($nxtarg ne '>') {
        error "expecting '<'";
        return 0;
    }
    my @node = ($SEQUENCE, $bound, $type, curr_scope);
    \@node;
}


sub parse_type {
    my ($typename, $argref, $symtreeref) = @_;
    my $type;
    if ($typename =~ /^string<(\d+)>$/) {   # bounded string
        my @bou_str_node = ($BOUNDED_STRING, $1, 0, curr_scope);
        $type = \@bou_str_node;
    } elsif ($typename eq 'sequence') {
        $type = parse_sequence($argref, $symtreeref);
    } else {
        $type = find_node($typename, $symtreeref);
    }
    $type;
}


sub parse_members {
    # params:   \@symbols, \@arg, \@struct
    # returns:  -1 for error;
    #            0 for success with enclosing scope still open;
    #            1 for success with enclosing scope closed (i.e. seen '};')
    my ($symtreeref, $argref, $structref) = @_;
    my @arg = @{$argref};
    while (@arg) {    # We're up here for a TYPE name
        my $first_thing = shift @arg;  # but it could also be '}'
        if ($first_thing eq '}') {
            print "Hey, parse_members has seen a '}' !\n";
            return 1;   # return value signals closing of scope.
        }
        my $component_type = parse_type($first_thing, \@arg, $symtreeref);
        if (! $component_type) {
            error "unknown type $first_thing";
            return -1;  # return value signals error.
        }
        while (@arg) {    # We're here for VARIABLE name(s)
            my $component_name = shift @arg;
            last if ($component_name eq '}');
            check_name($component_name);
            my @dimensions = ();
            my $nxtarg;
            while (@arg) {    # We're here for a variable's DIMENSIONS
                $nxtarg = shift @arg;
                if ($nxtarg eq '[') {
                    my $dim = shift @arg;
                    check_name($dim, "dimension");
                    if (shift @arg ne ']') {
                        error "expecting ']'";
                        return -1;
                    }
                    push @dimensions, $dim;
                } elsif ($nxtarg eq ',' || $nxtarg eq ';') {
                    last;
                } else {
                    error "component declaration syntax error";
                    return -1;
                }
            }
            my @node = ($component_type, $component_name, [ @dimensions ]);
            push @{$structref}, \@node;
            last if ($nxtarg eq ';');
        }
    }
    0;   # return value signals success with scope still open.
}


sub Parse_File {
    # Returns a reference to the symbol node array of the outermost
    # declarations encountered.
    my $file = shift;
    my @dummy;
    my $in;
    if ($file) {                  # Process a new file (or includefile)
        push @infilename, $file;
        $in = $fh[$#infilename];
        open($in, $file) or die "Cannot open file $file\n";
        print("-- processing: $file\n") if ($verbose);
    } else {
        $in = $fh[$#infilename];  # Process a module or interface within file.
    }

    my $line;
    my @symbols = ();      # symbol tree that will be constructed here
    my @struct = ();       # temporary storage for struct/union/exception
    my @typestack = ();    # typestack and namestack move in parallel.
    my @namestack = ();    # They are aux. vars for struct/union processing.
    while (($line = getline($in))) {
        # print "$line\n";
        my @arg = idlsplit($line);
        my $kw = shift @arg;
# print (join ('|', @arg) . "\n");
        if ($kw eq '#') {
            my $directive = shift @arg;
            if ($directive eq 'include') {
                my $filename = shift @arg;
                if (substr($filename, 0, 1) ne '"') {
                    error "include file name should be given in double quotes";
                } else {
                    $filename = substr($filename, 1);
                    if (substr($filename, length($filename) - 1) ne '"') {
                        error "missing closing quote";
                    } else {
                        $filename = substr($filename, 0, length($filename) - 1);
                    }
                }
                my $inside_includefile = ($#infilename != 0);
                unshift @prev_symroots, \@symbols;
                my $incfile_contents_ref = Parse_File($filename);
                if (! $incfile_contents_ref) {
                    die "can't go on, sorry\n";
                }
                shift @prev_symroots;
                my @include_node = ($INCFILE, $filename,
                                    $incfile_contents_ref, curr_scope);
                push @symbols, \@include_node;
            } elsif ($directive eq 'pragma') {
                my $prefix = shift @arg;
                if ($prefix ne 'prefix') {
                    print "unknown \#pragma $prefix\n";
                    next;
                }
                $prefix = shift @arg;
                if (substr($prefix, 0, 1) ne '"') {
                    error "prefix should be given in double quotes";
                } else {
                    $prefix = substr($prefix, 1);
                    if (substr($prefix, length($prefix) - 1) ne '"') {
                        error "missing closing quote";
                    } else {
                        $prefix = substr($prefix, 0, length($prefix) - 1);
                    }
                }
                my @prefix_node = ($PRAGMA_PREFIX, $prefix, 0, curr_scope);
                push @symbols, \@prefix_node;
            } else {
                print "ignoring preprocessor directive \#$directive\n";
            }
            next;
        } elsif ($kw eq '}') {
            if (shift @arg ne ';') {
                error "missing ';'";
            }
            if ($#typestack < 0) {  # must be closing of module or interface
                if ($#scopestack < 0) {
                    error('unexpected };');
                } else {
                    pop @scopestack;
                }
                return \@symbols;
            }
            my $type = pop @typestack;
            my $name = pop @namestack;
            if ($type == $STRUCT or $type == $UNION or $type == $EXCEPTION) {
                my @structnode = ($type, $name, [ @struct ], curr_scope);
                push @symbols, [ @structnode ];
                @struct = ();
            } else {
                error "encountered }; while not expecting it (?)";
            }
            next;
        } elsif ($kw eq 'module') {
            my $name = shift @arg;
            check_name $name;
            error("expecting '{'") if (shift(@arg) ne '{');
            my @symnode = ($MODULE, $name, 0, curr_scope);
            push @symbols, \@symnode;
            unshift @prev_symroots, \@symbols;
            push @scopestack, \@symnode;
            my $module_contents_ref = Parse_File("");
            if (! $module_contents_ref) {
                die "can't go on, sorry\n";
            }
            shift @prev_symroots;
            my $module_ref = $symbols[$#symbols];
            $$module_ref[$SUBORDINATES] = $module_contents_ref;
            next;
        } elsif ($kw eq 'interface') {
            my $name = shift @arg;
            check_name $name;
            error("expecting '{'") if (pop(@arg) ne '{');
            my @ancestor = ();
            if (@arg) {    # we have ancestors
                if (shift @arg ne ':') {
                    error "syntax error";
                    next;
                } elsif (! @arg) {
                    error "expecting ancestor(s)";
                    next;
                }
                for ($i = 0; $i < @arg; $i++) {
                    my $name = $arg[$i];
                    check_name($name, "ancestor name");
                    my $ancestor_node = find_node($name, \@symbols);
                    if (! $ancestor_node) {
                        error "could not find ancestor $name";
                        next;
                    }
                    push @ancestor, $ancestor_node;
                    if ($i < $#arg) {
                        if ($arg[++$i] ne ',') {
                            error "expecting comma separated list of ancestors";
                            last;
                        }
                    }
                }
            }
            my @symnode = ($INTERFACE, $name, 0, curr_scope);
            push @symbols, \@symnode;
            unshift @prev_symroots, \@symbols;
            push @scopestack, \@symnode;
            my $iface_contents_ref = Parse_File("");
            if (! $iface_contents_ref) {
                die "can't go on, sorry\n";
            }
            shift @prev_symroots;
            my @iface_tuple = ([ @ancestor ], $iface_contents_ref);
            my $iface_ref = $symbols[$#symbols];
            $$iface_ref[$SUBORDINATES] = [ @iface_tuple ];
            next;
        } elsif ($kw eq 'struct' or $kw eq 'exception') {
            my $type = ($kw eq 'struct' ? $STRUCT : $EXCEPTION);
            my $name = shift @arg;
            check_name $name;
            if (shift @arg ne '{') {
                error "expecting '{'";
                next;
            }
            push @namestack, $name;
            push @typestack, $type;
            @struct = ();
            if (@arg) {
                if ($arg[0] eq '}' or
                        parse_members(\@symbols, \@arg, \@struct) == 1) {
                    # end of type declaration was encountered
                    my @node = ($type, $name, [ @struct ], curr_scope);
                    push @symbols, \@node;
                    pop @namestack;
                    pop @typestack;
                    @struct = ();
                }
            }
            next;
        } elsif ($kw eq 'union') {
            push @typestack, $UNION;
            my $typename = shift @arg;
            check_name($name, "type name");
            push @namestack, $typename;
            if (shift @arg ne 'switch') {
                error "expecting keyword 'switch'";
                next;
            } elsif (shift @arg ne '(') {
                error "expecting '('";
                next;
            }
            my $switchtypename = shift @arg;
            my $switchtype = find_node($switchtypename, \@symbols);
            if (! $switchtype) {
                error "unknown type of switch variable";
                next;
            } elsif (isnode $switchtype) {
                my $typ = ${$switchtype}[$TYPE];
                if ($typ < $BOOLEAN ||
                     ($typ > $ULONG && $typ != $ENUM && $typ != $TYPEDEF)) {
                    error "illegal switch variable type (node; $typ)";
                    next;
                }
            } elsif ($switchtype < $BOOLEAN || $switchtype > $ULONG) {
                error "illegal switch variable type ($switchtype)";
                next;
            }
            error("expecting ')'") if (shift @arg ne ')');
            error("expecting '{'") if (shift @arg ne '{');
            error("ignoring excess characters") if (@arg);
            @struct = ($switchtype);
            next;
        }
        if (! require_end_of_stmt(\@arg, $in)) {
            error "statement not terminated";
            next;
        }
        if ($kw eq 'const') {
            my $type = shift @arg;
            my $name = shift @arg;
            if (shift(@arg) ne '=') {
                error "expecting '='";
                next;
            }
            my $typething = find_node($type, \@symbols);
            next if (! $typething);
            my @tuple = ($typething, [ @arg ]);
            if (isnode $typething) {
                my $id = ${$typething}[$TYPE];
                if ($id < $ENUM || $id > $TYPEDEF) {
                    error "expecting type";
                    next;
                }
            }
            my @symnode = ($CONST, $name, \@tuple, curr_scope);
            push @symbols, \@symnode;
        } elsif ($kw eq 'typedef') {
            my $oldtype = shift @arg;
            # check_name($oldtype, "name of original type");
            # TO BE DONE: oldtype is STRUCT or UNION
            my $existing_typenode = parse_type($oldtype, \@arg, \@symbols);
            if (! $existing_typenode) {
                error "unknown type $oldtype";
                next;
            }
            my $newtype = shift @arg;
            check_name($newtype, "name of newly defined type");
            my @dimensions = ();
            while (@arg) {
                if (shift(@arg) ne '[') {
                    error "expecting '['";
                    last;
                }
                my $dim = shift @arg;
                push @dimensions, $dim;
                if (shift(@arg) ne ']') {
                    error "expecting ']'";
                }
            }
            my @tuple = ($existing_typenode, [ @dimensions ]);
            my @node = ($TYPEDEF, $newtype, \@tuple, curr_scope);
            push @symbols, \@node;
        } elsif ($kw eq 'case' or $kw eq 'default') {
            my @node;
            my @casevals = ();
            if ($kw eq 'case') {
                while (@arg) {
                    push @casevals, shift @arg;
                    if (shift @arg ne ':') {
                        error "expecting ':'";
                        last;
                    }
                    last if ($arg[0] ne 'case');
                    shift @arg;
                }
                @node = ($CASE, "", \@casevals);
            } else {
                if (shift @arg ne ':') {
                    error "expecting ':'";
                    next;
                }
                @node = ($DEFAULT, "", 0);
            }
            push @struct, \@node;
            if (@arg) {
                if (parse_members(\@symbols, \@arg, \@struct) == 1) {
                    # end of type declaration was encountered
                    if ($#typestack < 0) {
                        error "internal error 1";
                        next;
                    }
                    my $type = pop @typestack;
                    my $name = pop @namestack;
                    if ($type != $UNION) {
                        error "internal error 2";
                        next;
                    }
                    my @unionnode = ($type, $name, [ @struct ], curr_scope);
                    push @symbols, \@unionnode;
                    @struct = ();
                }
            }
        } elsif ($kw eq 'enum') {
            my $typename = shift @arg;
            check_name($typename, "type name");
            my @values = ();
            if (shift @arg ne '{') {
                error("expecting '{'");
                next;
            } elsif (pop @arg ne '}') {
                error("expecting '}'");
                next;
            }
            while (@arg) {
                my $lit = shift @arg;
                push @values, $lit;
                if (@arg and shift @arg ne ',') {
                    error "expecting ','";
                    last;
                }
            }
            my @symnode = ($ENUM, $typename, [ @values ], curr_scope);
            push @symbols, [ @symnode ];
        } elsif ($kw eq 'readonly' or $kw eq 'attribute') {
            my $readonly = 0;
            if ($kw eq 'readonly') {
                if (shift(@arg) ne 'attribute') {
                    error "expecting keyword 'attribute'";
                    next;
                }
                $readonly = 1;
            }
            my $typename = shift @arg;
            my $type = parse_type($typename, \@arg, \@symbols);
            if (! $type) {
                error "unknown type $typename";
                next;
            }
            my @subord = ($readonly, $type);
            my $name = shift @arg;
            check_name $name;
            my @node = ($ATTRIBUTE, $name, \@subord, curr_scope);
            push @symbols, \@node;
        } elsif ($kw eq 'oneway' || $kw eq 'void' or $line =~ /\(.*\);$/) {
            # Method
            my $rettype;
            my @subord;
            if ($kw eq 'oneway') {
                if (shift(@arg) ne 'void') {
                    error "expecting keyword 'void' after oneway";
                    next;
                }
                $rettype = $ONEWAY;
            } elsif ($kw eq 'void') {
                $rettype = $VOID;
            } else {
                $rettype = parse_type($kw, \@arg, \@symbols);
                if (! $rettype) {
                    error "unknown return type $kw";
                    next;
                }
            }
            my $name = shift @arg;
            check_name($name, "method name");
            if (shift(@arg) ne '(') {
                error "expecting opening parenthesis";
                next;
            } elsif (pop(@arg) ne ')') {
                error "expecting closing parenthesis";
                next;
            }
            @subord = ($rettype);
            my @exception_list = ();
            my $expecting_exception_list = 0;
            while (@arg) {
                my $m = shift @arg;
                my $typename = shift @arg;
                my $pname = shift @arg;
                if ($m eq ')') {
                    if ($typename ne 'raises') {
                        error "expecting keyword 'raises'";
                    } elsif ($pname ne '(') {
                        error "expecting '(' after 'raises'";
                    } else {
                        $expecting_exception_list = 1;
                    }
                    last;
                }
                my $pmode = ($m eq 'in' ? $IN : $m eq 'out' ? $OUT :
                             $m eq 'inout' ? $INOUT : 0);
                if (! $pmode) {
                    error("illegal mode of parameter $pname");
                    last;
                }
                my $ptype = find_node($typename, \@symbols);
                if (! $ptype) {
                    error "unknown type of parameter $pname";
                    last;
                }
                my @param_node = ($ptype, $pname, $pmode);
                push @subord, \@param_node;
                shift @arg if ($arg[0] eq ',');
            }
            if ($expecting_exception_list) {
                while (@arg) {
                    my $exc_name = shift @arg;
                    my $exc_type = find_node($exc_name, \@symbols);
                    if (! $exc_type) {
                        error "unknown exception $exc_name";
                        last;
                    } elsif (${$exc_type}[$TYPE] != $EXCEPTION) {
                        error "cannot raise $exc_name (not an exception)";
                        last;
                    }
                    push @exception_list, $exc_type;
                    if (@arg and shift @arg ne ',') {
                        error "expecting ',' in exception list";
                        last;
                    }
                }
            }
            push @subord, \@exception_list;
            my @node = ($METHOD, $name, \@subord, curr_scope);
            push @symbols, \@node;
        } else {                          # Data
            if ($#typestack < 0) {
                error "unexpected declaration";
                next;
            }
            my $type = $typestack[$#typestack];
            if ($type != $STRUCT and $type != $UNION and $type != $EXCEPTION) {
                error "unexpected declaration within $predef_types[$type]";
                next;
            }
            unshift @arg, $kw;   # put type back into @arg
            if (parse_members(\@symbols, \@arg, \@struct) == 1) {
                # end of type declaration was encountered
                pop @typestack;
                my $name = pop @namestack;
                my @node = ($type, $name, [ @struct ], curr_scope);
                push @symbols, [ @node ];
                @struct = ();
            }
        }
    }
    if ($file) {
        close $in;
        pop @infilename;
    }
    if ($n_errors) {
        return 0;
    }
    \@symbols;
}


sub require_end_of_stmt {
    my ($argref, $file) = @_;
    if ($$argref[$#$argref] eq ';') {
        pop @$argref;
        return 1;
    }
    my $line;
    while ($$argref[$#$argref] ne ';') {
        last if (! ($line = getline($file)));
        push @$argref, idlsplit($line);
    }
    if ($$argref[$#$argref] eq ';') {
        pop @$argref;
        return 1;
    }
    0;
}


sub isnode {
    my $node_ref = shift;
    if (! $node_ref or $node_ref < $NUMBER_OF_TYPES) {
        return 0;
    }
    my @node = @{$node_ref};
    if ($#node != 3
        or $node[$TYPE] < $BOOLEAN or $node[$TYPE] >= $NUMBER_OF_TYPES) {
        return 0;
    }
    # NB: The ($#node != 3) means that component descriptors of 
    # structs/unions/exceptions and parameter descriptors of methods
    # do not qualify as nodes.
    1;
}


sub find_node_recursive {   # auxiliary to find_node()
    my ($name, $rootref) = @_;
    my $predef_type_id = predef_type($name);
    if ($predef_type_id) {
        return $predef_type_id;
    }
    if (! $rootref) {
        return 0;
    }
    my $return_node;
    if (! isnode($rootref)) {
        foreach $node (@{$rootref}) {
            if (($return_node = find_node_recursive($name, $node))) {
                return $return_node;
            }
        }
        return 0;
    }
    while (1) {
        my $dot = index $name, '.';
        last if ($dot < 0);
        if ($dot == 0) {
            error "syntax error at prefix";
            return 0;
        }
        my $this_prefix = substr($name, 0, $dot);
        if (! ($rootref = find_node_recursive($this_prefix, $rootref))) {
            return 0;
        }
        my $prefix_nodetype = ${$rootref}[$TYPE];
        if ($prefix_nodetype != $MODULE and $prefix_nodetype != $INTERFACE) {
            error "prefix $prefix is not a module or interface";
            return 0;
        }
        $name = substr($name, $dot + 1);
    }
    if ($name eq ${$rootref}[$NAME]) {
       return $rootref;
    }
    my $type = ${$rootref}[$TYPE];
    if ($type eq $INTERFACE or $type eq $MODULE or $type eq $INCFILE) {
        return find_node_recursive($name, $$rootref[$SUBORDINATES]);
    }
    0;
}

sub find_node {
    # Returns a reference to the defining node, or a type id value
    # if the name given is a CORBA predefined type name.
    # Returns 0 if the name could not be identified.
    my ($name, $current_symtree_ref) = @_;

    my $result_node_ref = find_node_recursive($name, $current_symtree_ref);
    if ($result_node_ref) {
        return $result_node_ref;
    }
    foreach $noderef (@prev_symroots) {
        $result_node_ref = find_node_recursive($name, $noderef);
        if ($result_node_ref) {
            return $result_node_ref;
        }
    }
    0;
}



sub error {
    my $message = shift;
    print "$infilename[$currfile] line $line_number[$currfile]: $message\n";
    $n_errors++;
}


# Dump_Symbols and auxiliary subroutines

sub dsemit {
    print shift;
}

sub dsdent {
    dsemit(' ' x ($dsindentlevel * 3));
    dsemit shift;
}

sub dsindent {
    dsdent shift;
    $dsindentlevel++;
}

sub dsdedent {
    $dsindentlevel--;
    dsdent shift;
}


sub Dump_Symbols {
    my $sym_array_ref = shift;
    if (! $sym_array_ref) {
        dsemit "\nds: encountered empty elem (returning)\n";
        return;
    }
    if (not isnode $sym_array_ref) {
        foreach $elem (@{$sym_array_ref}) {
            Dump_Symbols $elem;
        }
        return;
    }
    my @node = @{$sym_array_ref};
    my $type = $node[$TYPE];
    my $name = $node[$NAME];
    dsdent(sprintf("%-10s%-19s ", $predef_types[$type], $name));
    my $subord = $node[$SUBORDINATES];
    my @arg = @{$subord};
    if ($type == $TYPEDEF) {
        my $first_elem = $arg[0];
        my $dimref = $arg[1];
        dsemit typeof($first_elem);
        if ($dimref and @{$dimref}) {
            foreach $dim (@{$dimref}) {
                dsemit('[' . $dim . ']');
            }
        }
        dsemit "\n";
    } elsif ($type == $CONST) {
        dsemit(typeof($arg[0]) . " = " .
               join(' ', @{$arg[1]}) . "\n");
    } elsif ($type == $ENUM) {
        foreach $val (@arg) {
            dsemit "$val ";
        }
        dsemit "\n";
    } elsif ($type == $STRUCT || $type == $UNION || $type == $EXCEPTION) {
        if ($type == $UNION) {
            dsemit("switch (" . typeof(shift @arg) . ")");
        }
        dsemit "\n";
        $dsindentlevel++;
        my $had_case = 0;
        while (@arg) {
            my $node = shift @arg;
            my $type = $$node[$TYPE];
            my $name = $$node[$NAME];
            my $suboref = $$node[$SUBORDINATES];
            if ($type == $CASE || $type == $DEFAULT) {
                if ($had_case) {
                    $dsindentlevel--;
                } else {
                    $had_case = 1;
                }
                if ($type == $CASE) {
                    foreach $case (@{$suboref}) {
                       dsdent "case $case:\n";
                    }
                } else {
                    dsdent "default:\n";
                }
                $dsindentlevel++;
            } else {
                foreach $dim (@{$suboref}) {
                    $name .= '[' . $dim . ']';
                }
                dsdent(sprintf "%-19s%s\n", typeof($type), $name);
            }
        }
        $dsindentlevel -= $had_case + 1;
    } elsif ($type == $INCFILE || $type == $MODULE) {
        dsemit "\n";
        $dsindentlevel++;
        foreach $component (@arg) {
            Dump_Symbols $component;
        }
        $dsindentlevel--;
    } elsif ($type == $INTERFACE) {
        my @ancestors = @{$arg[0]};
        if (@ancestors) {
            dsemit " :";
            foreach $elder (@ancestors) {
                dsemit " $elder";
            }
        }
        dsemit "\n";
        $dsindentlevel++;
        foreach $declaration (@{$arg[1]}) {
            Dump_Symbols $declaration;
        }
        $dsindentlevel--;
    } elsif ($type == $ATTRIBUTE) {
        dsemit typeof($arg[1]);
        dsemit("  readonly") if ($arg[0]);
        dsemit "\n";
    } elsif ($type == $METHOD) {
        my $t = shift @arg;
        my $rettype = ($t == $ONEWAY ? 'oneway' :
                       $t == $VOID   ? 'void'   : typeof($t));
        dsemit($rettype . " (");
        while ($#arg > 0) {
            my $pnode = shift @arg;
            my $ptype = typeof($$pnode[$TYPE]);
            my $pname = $$pnode[$NAME];
            my $m     = $$pnode[$SUBORDINATES];
            my $pmode = ($m == $IN ? 'in' : $m == $OUT ? 'out' : 'inout');
            dsemit "$pmode $ptype $pname";
            if ($#arg > 0) {
                dsemit ",";
            }
        }
        dsemit ")";
        my @exc_list = @{shift @arg};
        if (@exc_list) {
            dsemit " raises (";
            foreach $exc (@exc_list) {
                dsemit(${$exc}[$NAME] . " ");
            }
            dsemit ")";
        }
        dsemit "\n";
    } else {
        print "Dump_Symbols: unknown type value $type\n";
    }
}



##### EXPERIMENTAL ######  untested -- under development ####################

$user_sub_ref = 0;
$traverse_includefiles = 0;

sub traverse {
    my ($symroot, $scope, $inside_includefile) = @_;
    if (! $symroot) {
        print "\ntraverse_tree: encountered empty elem (returning)\n";
        return;
    } elsif (is_elementary_type $symroot) {
        &{$user_sub_ref}($symroot, $scope, $inside_includefile);
        return;
    } elsif (not isnode $symroot) {
        foreach $decl (@{$symroot}) {
            traverse($decl, $scope, $inside_includefile);
        }
        return;
    }
    &{$user_sub_ref}($symroot, $scope, $inside_includefile);
    my @node = @{$symroot};
    my $type = $node[$TYPE];
    my $name = $node[$NAME];
    my $subord = $node[$SUBORDINATES];
    my @arg = @{$subord};
    if ($type == $INCFILE) {
        traverse($subord, $scope, 1) if ($traverse_includefiles);
    } elsif ($type == $MODULE) {
        if ($scope) {
            $scope .= '.' . $name;
        } else {
            $scope = $name;
        }
        foreach $decl (@arg) {
            traverse($decl, $scope, $inside_includefile);
        }
    } elsif ($type == $INTERFACE) {
        my @ancestors = @{$arg[0]};
        if (@ancestors) {
            foreach $elder (@ancestors) {
                &{$user_sub_ref}($elder, $scope, $inside_includefile);
            }
        }
        if ($scope) {
            $scope .= '.' . $name;
        } else {
            $scope = $name;
        }
        foreach $decl (@{$arg[1]}) {
            traverse($decl, $scope, $inside_includefile);
        }
    }
}

sub traverse_tree {
    my $sym_array_ref = shift;
    $user_sub_ref = shift;
    if (@_) {
        $traverse_includefiles = shift;
    }
    traverse($sym_array_ref, "", 0);
}


1;

