use strict;
use warnings;
use Test::More;
use Parallel::Pipes;
use File::Temp ();
use Time::HiRes ();
use Parallel::Pipes::App;

my $subtest = sub {
    my $number_of_pipes = shift;
    my $tempdir = File::Temp::tempdir(CLEANUP => 1);

    my @queue = 0..30;
    my @back;
    my $app = Parallel::Pipes::App->new(
        workers => $number_of_pipes,
        dequeue => sub { @queue ? shift @queue : () },
        process => sub {
            my $num = shift;
            Time::HiRes::sleep(0.01);
            open my $fh, ">>", "$tempdir/file.$$" or die;
            print {$fh} "$num\n";
            $num;
        },
        on_done => sub {
            my $num = shift;
            push @back, $num;
        },
    );
    $app->run;

    my @file = glob "$tempdir/file*";
    my @num;
    for my $f (@file) {
        open my $fh, "<", $f or die;
        chomp(my @n = <$fh>);
        push @num, @n;
    }
    @num = sort { $a <=> $b } @num;
    @back = sort { $a <=> $b } @back;

    is @file, $number_of_pipes;
    is_deeply \@num, [0..30];
    is_deeply \@back, [0..30];

    if ($number_of_pipes == 1) {
        is $file[0], "$tempdir/file.$$";
    }
};

subtest number_of_pipes1 => sub { $subtest->(1) };
subtest number_of_pipes5 => sub { $subtest->(5) } unless $^O eq 'MSWin32';

done_testing;
