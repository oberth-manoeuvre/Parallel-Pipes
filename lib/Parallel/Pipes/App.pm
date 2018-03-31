package Parallel::Pipes::App;
use strict;
use warnings;
use Parallel::Pipes;

sub new {
    my ($class, %args) = @_;
    bless \%args, $class;
}

sub run {
    my $self = shift;
    my $pipes = Parallel::Pipes->new($self->{workers}, $self->{process});
    my $dequeue; $dequeue = sub {
        if (my ($data) = $self->{dequeue}->()) {
            return $data;
        }
        if (my @written = $pipes->is_written) {
            my @ready = $pipes->is_ready(@written);
            $self->{on_done}->($_) for map $_->read, @ready;
            return $dequeue->();
        }
        return;
    };
    while (my ($data) = $dequeue->()) {
        my @ready = $pipes->is_ready;
        $self->{on_done}->($_) for map $_->read, grep $_->is_written, @ready;
        $ready[0]->write($data);
    }
    $pipes->close;
    return 1;
}

1;
