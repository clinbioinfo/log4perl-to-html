#!/usr/bin/perl

use strict;
use Carp;
use Cwd;
use Pod::Usage;
use Data::Dumper;
use File::Copy;
use File::Path;
use File::Basename;
use File::Spec;
use Term::ANSIColor;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use FindBin;
use Template;
use Sys::Hostname;

use lib "$FindBin::Bin/../lib";

use constant TRUE => 1;
use constant FALSE => 0;

use constant STATE_IDX => 0;
use constant DATE_IDX => 4;
use constant TIME_IDX => 5;
use constant PROGRAM_FILE_IDX => 10;
use constant LINE_NUMBER_IDX => 11;
use constant STATEMENT_IDX => 12;

use constant DEFAULT_VERBOSE => TRUE;

use constant DEFAULT_COMMENT => 'N/A';

use constant DEFAULT_TEMPLATE_FILE => "$FindBin::Bin/../template/log4perl_to_html_tmpl.tt";

use constant DEFAULT_USERNAME => getlogin || $ENV{USER};

use constant DEFAULT_OUTDIR => '/tmp/' . DEFAULT_USERNAME . '/' . File::Basename::basename($0) . '/'. time();

use constant DEFAULT_ADMIN_EMAIL => 'sundaram.medimmune@gmail.com';

use constant DEFAULT_WEB_SERVER_DIR => '/var/www/html';

use constant DEFAULT_SERVER_OWNER => 'www-data';


$|=1; ## do not buffer output stream

## Parse command line options
my ($man, $help, $infile, $outfile, $template_file, $outdir, $web_server_dir, $username, $comment, $install_dir, $server_owner);

my $results = GetOptions (
    'help|h'           => \$help,
    'man|m'            => \$man,
    'infile=s'         => \$infile,
    'outfile=s'        => \$outfile,
    'outdir=s'         => \$outdir,
    'template_file=s'  => \$template_file,
    'web_server_dir=s' => \$web_server_dir,
    'username=s'       => \$username,
    'comment=s'        => \$comment,
    'install_dir=s'    => \$install_dir,
    'server_owner=s'   => \$server_owner,
    );

my $hostname = hostname();
my $start_date;
my $end_date;

&checkCommandLineArguments();

if (!-e $template_file){
    confess("template file '$template_file' does not exist");
}

my $lookup = {};

my $info_ctr = 0;
my $warn_ctr = 0;
my $error_ctr = 0;
my $fatal_ctr = 0;
my $debug_ctr = 0;

my $overall_time_change = FALSE;
my $start_time;
my $end_time;

if (!defined($outfile)){

    $outfile = $outdir . '/' . File::Basename::basename($infile);

    $outfile =~ s|\.log|\.html|;
}

my $records = [];

&parseLogfile();

&convert();

print "The output file is '$outfile'\n";

&set_up_install();

&install_html_file();

exit(0);

##-----------------------------------------------------------
##
##    END OF MAIN -- SUBROUTINES FOLLOW
##
##-----------------------------------------------------------

sub parseLogfile {

    open (INFILE, "<$infile") || die "Could not open file '$infile' : $!";
   
    my $lineCtr = 0;

    ## Sample line:
    ## INFO - [5 | 2015/10/31 16:06:30 | ctix | 2162] ../lib/Database/Config/Record.pm 125 Instantiated Database::Config::Record

    my $previous_time;

    while (my $line = <INFILE>){

        chomp $line;
        
        $lineCtr++;
        
        my $state;
        my $date;
        my $time;
        my $program_file;
        my $line_number;
        my $statement;
        my @statement_list;
        my $time_changed = FALSE;

        my @parts = split(/\s+/, $line);

        my $ctr = 0;

        foreach my $part (@parts){

            if ($ctr == STATE_IDX){
                $state = $part;

                $debug_ctr++ if ($state eq 'DEBUG');
                $info_ctr++ if ($state eq 'INFO');
                $warn_ctr++ if ($state eq 'WARN');
                $error_ctr++ if ($state eq 'ERROR');
                $fatal_ctr++ if ($state eq 'FATAL');
            }
            elsif ($ctr == DATE_IDX){
                $date = $part;
                if ($lineCtr == 1){
                    $start_date = $date;
                }

                $end_date = $date;
            }
            elsif ($ctr == TIME_IDX){
                $time = $part;

                if ($lineCtr == 1){
                    $start_time = $time;
                }


                $end_time = $time;

                if (defined($previous_time)){
                    if ($time ne $previous_time){
                        $time_changed = TRUE;
                        $overall_time_change = TRUE;
                    }
                }
                $previous_time = $time;
            }
            elsif ($ctr == PROGRAM_FILE_IDX){
                $program_file = $part;
                if ($program_file =~ m|\S+\.\./(\S+)|){
                    $program_file = $1;
                }
            }
            elsif ($ctr == LINE_NUMBER_IDX){
                $line_number = $part;
            }
            elsif ($ctr > LINE_NUMBER_IDX){
                push(@statement_list, $part);
            }

            $ctr++;
        }

        $statement = join(' ' , @statement_list);

        push(@{$records}, [$state, $date, $time, $program_file, $line_number, $statement, $time_changed]);

    }

    close INFILE;

}


sub convert {

    my $tt = new Template({ABSOLUTE => 1});
    if (!defined($tt)){
        confess ("Could not instantiate TT");
    }
    
    &loadTemplateLookup(@_);

    $tt->process($template_file, $lookup,  $outfile) || confess("Encountered the following Template::process error:" . $tt->error());

    print ("Created file '$outfile' using template file '$template_file'\n");   
}

sub loadTemplateLookup {

    my $date_created = localtime();

    my $method_created = File::Spec->rel2abs($0);

    my $infile_basename = File::Basename::basename($infile);

    my $infile_url = $infile;

    $infile_url =~ s|$web_server_dir/|/|;

    $lookup = {
        admin_email_address => DEFAULT_ADMIN_EMAIL,
        method_created      => $method_created,
        date_created        => $date_created,
        infile              => $infile,
        infile_basename     => $infile_basename,
        infile_url          => $infile_url,
        username            => $username,
        records             => $records,
        start_date          => $start_date,
        end_date            => $end_date,
        debug_count         => $debug_ctr,
        info_count          => $info_ctr,
        warn_count          => $warn_ctr,
        error_count         => $error_ctr,
        fatal_count         => $fatal_ctr,
        overall_time_change => $overall_time_change,
        start_time          => $start_time,
        end_time            => $end_time,
        comment             => $comment
    };    
}

sub printGreen {

    my ($msg) = @_;
    print color 'green';
    print $msg . "\n";
    print color 'reset';
}

sub printYellow {

    my ($msg) = @_;
    print color 'yellow';
    print $msg . "\n";
    print color 'reset';
}

sub printBoldRed {

    my ($msg) = @_;
    print color 'bold red';
    print $msg . "\n";
    print color 'reset';
}

sub checkCommandLineArguments {
   
    if ($man){
    	&pod2usage({-exitval => 1, -verbose => 2, -output => \*STDOUT});
    }
    
    if ($help){
    	&pod2usage({-exitval => 1, -verbose => 1, -output => \*STDOUT});
    }

    if (!defined($server_owner)){

        $server_owner = DEFAULT_SERVER_OWNER;

        printYellow("--server_owner was not specified and therefore was set to default '$server_owner'");        
    }

    if (!defined($web_server_dir)){

        $web_server_dir = DEFAULT_WEB_SERVER_DIR;

        printYellow("--web_server_dir was not specified and therefore was set to default '$web_server_dir'");        
    }

    if (!defined($install_dir)){

        $install_dir = $web_server_dir . '/log4perl-to-html';

        printYellow("--install_dir was not specified and therefore was set to default '$install_dir'");        
    }

    if (!defined($outdir)){

        $outdir = DEFAULT_OUTDIR;

        printYellow("--outdir was not specified and therefore was set to default '$outdir'");
    }

    if (!defined($username)){

        $username = DEFAULT_USERNAME;

        printYellow("--username was not specified and therefore was set to default '$username'");
    }

    if (!-e $outdir){

        mkpath ($outdir) || die "Could not create output directory '$outdir' : $!";

        printYellow("Created output directory '$outdir'");
    }

    if (!defined($template_file)){
        
        $template_file = DEFAULT_TEMPLATE_FILE;

        printYellow("--template_file was not specified and therefore was set to default '$template_file'");
    }

    if (!defined($comment)){
        
        $comment = DEFAULT_COMMENT;

        printYellow("--comment was not specified and therefore was set to default '$comment'");
    }

    my $fatalCtr=0;

    if (!defined($infile)){
        
        printBoldRed("--infile was not specified");

        $fatalCtr++;       
    }
    else {

        &checkInfileStatus($infile);
    }

    $infile = File::Spec->rel2abs($infile);

    if ($fatalCtr > 0 ){

    	printBoldRed("Required command-line arguments were not specified");

        exit(1);
    }
}

sub checkInfileStatus {

    my ($infile) = @_;
    
    if (!defined($infile)){
        die("infile was not defined");
    }

    my $errorCtr = 0 ;

    if (!-e $infile){
        
        printBoldRed("input file '$infile' does not exist");
        
        $errorCtr++;
    }
    else {
        if (!-f $infile){
            
            printBoldRed("'$infile' is not a regular file");
            
            $errorCtr++;
        }

        if (!-r $infile){
            
            printBoldRed("input file '$infile' does not have read permissions");
            
            $errorCtr++;
        }

        if (!-s $infile){
            
            printBoldRed("input file '$infile' does not have any content");
            
            $errorCtr++;
        }
    }

    if ($errorCtr > 0){
        
        printBoldRed("Encountered issues with input file '$infile'");
        
        confess;
    }
}

sub checkOutdirStatus {

    my ($outdir) = @_;

    if (!-e $outdir){
        
        mkpath($outdir) || die "Could not create output directory '$outdir' : $!";
        
        printYellow("Created output directory '$outdir'");        
    }
    
    if (!-d $outdir){
        
        printBoldRed("'$outdir' is not a regular directory");        
    }
}

sub set_up_install {

    if (!-e $web_server_dir){

        printBoldRed("Looks like you don't have a web server directory at '$web_server_dir'");

        exit(1);
    }

    if (!-e $install_dir){

        printYellow("Looks like the install directory '$install_dir' does not exist");

        my $cmd = "sudo mkdir -p $install_dir";

        execute_cmd($cmd);

        my $cmd2 = "sudo mkdir -p $install_dir/css";

        execute_cmd($cmd2);

        my $cmd3 = "sudo mkdir -p $install_dir/javascript/lib";

        execute_cmd($cmd3);

        my $cmd4 = "sudo mkdir -p $install_dir/javascript/app";

        execute_cmd($cmd4);

        my $cmd5 = "sudo cp $FindBin::Bin/../javascript/lib/jquery-1.10.2.min.js $install_dir/javascript/lib/.";

        execute_cmd($cmd5);        

        my $cmd6 = "sudo cp $FindBin::Bin/../javascript/app/log4perl_to_html.js $install_dir/javascript/app/.";

        execute_cmd($cmd6);        

        my $cmd7 = "sudo cp $FindBin::Bin/../css/*.css $install_dir/css/.";

        execute_cmd($cmd7);        

        my $cmd8 = "sudo chown -R $server_owner:$server_owner $install_dir";

        execute_cmd($cmd8);        
    }
}

sub install_html_file {

    my $cmd1 = "sudo cp $outfile $install_dir/.";

    execute_cmd($cmd1);        

    print "\nView it here:\n";
    print "http://localhost/log4perl-to-html/" . File::Basename::basename($outfile) . "\n";

}



sub execute_cmd {

    my ($ex) = @_;

    print ("About to execute '$ex'\n");

    print "About to execute '$ex'\n";
    
    eval {
        qx($ex);
    };

    if ($?){
        confess("Encountered some error while attempting to execute '$ex' : $! $@");
    }
}


__END__


=head1 NAME

 log4perl_to_html.pl - Convert a log4perl log file into .html format

=head1 SYNOPSIS

 perl bin/log4perl_to_html.pl --infile my.log

=head1 OPTIONS

=over 8

=item B<--help|-h>

  Print a brief help message and exits.

=item B<--man|-m>

  Prints the manual page and exits.

=back

=head1 DESCRIPTION

 This program will convert the Log4perl log file into HTML format.

=head1 CONTACT

 Jaideep Sundaram 
 
 Copyright Jaideep Sundaram

 Can be distributed under GNU General Public License terms

=cut
