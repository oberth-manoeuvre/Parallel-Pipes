#!/usr/bin/env perl
use 5.14.0;
use lib "lib", "../lib";
use Parallel::Pipes::App;

=head1 DESCRIPTION

This script crawles a web page, and follows links with specified depth.

You can easily change

  * a initial web page
  * the depth
  * how many crawlers

Moreover if you hack Crawler class, then it should be easy to implement

  * whitelist, blacklist for links
  * priority for links

=cut

package URLQueue {
    use constant WAITING => 1;
    use constant RUNNING => 2;
    use constant DONE    => 3;
    sub new {
        my ($class, %option) = @_;
        bless {
            max_depth => $option{depth},
            queue => { $option{url} => { state => WAITING, depth => 0 } },
        }, $class;
    }
    sub get {
        my $self = shift;
        my ($url) = grep { $self->{queue}{$_}{state} == WAITING } keys %{$self->{queue}};
        return unless $url;
        $self->_set_running($url);
        [ $url, $self->_depth_for($url) ];
    }
    sub _set_running {
        my ($self, $url) = @_;
        $self->{queue}{$url}{state} = RUNNING;
    }
    sub _depth_for {
        my ($self, $url) = @_;
        $self->{queue}{$url}{depth};
    }
    sub register {
        my ($self, $result) = @_;
        my $url   = $result->{url};
        my $depth = $result->{depth};
        my $next  = $result->{next};
        $self->{queue}{$url}{state} = DONE;
        return if $depth >= $self->{max_depth};
        for my $n (@$next) {
            next if exists $self->{queue}{$n};
            $self->{queue}{$n} = { state => WAITING, depth => $depth + 1 };
        }
    }
}

package Crawler {
    use Web::Scraper;
    use LWP::UserAgent;
    use Time::HiRes ();
    sub new {
        bless {
            http => LWP::UserAgent->new(timeout => 5, keep_alive => 1),
            scraper => scraper { process '//a', 'url[]' => '@href' },
        }, shift;
    }
    sub crawl {
        my ($self, $url, $depth) = @_;
        my ($res, $time) = $self->_elapsed(sub { $self->{http}->get($url) });
        if ($res->is_success and $res->content_type =~ /html/) {
            my $r = $self->{scraper}->scrape($res->decoded_content, $url);
            warn "[$$] ${time}sec \e[32mOK\e[m crawling depth $depth, $url\n";
            my @next = grep { $_->scheme =~ /^https?$/ } @{$r->{url}};
            return {url => $url, depth => $depth, next => \@next};
        } else {
            my $error = $res->is_success ? "content type @{[$res->content_type]}" : $res->status_line;
            warn "[$$] ${time}sec \e[31mNG\e[m crawling depth $depth, $url ($error)\n";
            return {url => $url, depth => $depth, next => []};
        }

    }
    sub _elapsed {
        my ($self, $cb) = @_;
        my $start = Time::HiRes::time();
        my $r = $cb->();
        my $end = Time::HiRes::time();
        $r, sprintf("%5.3f", $end - $start);
    }
}

my $queue = URLQueue->new(url => "https://www.cpan.org/", depth => 3);

my $app = Parallel::Pipes::App->new(
    workers => 10,
    dequeue => sub {
        $queue->get;
    },
    process => sub {
        my ($url, $depth) = @{$_[0]};
        state $crawler = Crawler->new;
        return $crawler->crawl($url, $depth);
    },
    on_done => sub {
        my $result = shift;
        $queue->register($result);
    },
);

$app->run;
