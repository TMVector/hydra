package Hydra::Plugin::GithubStatus;

use strict;
use parent 'Hydra::Plugin';
use HTTP::Request;
use JSON;
use LWP::UserAgent;
use Hydra::Helper::CatalystUtils;
use Data::Dump;

sub toGithubState {
    my ($buildStatus) = @_;
    if ($buildStatus == 0) {
        return "success";
    } elsif ($buildStatus == 3 || $buildStatus == 4 || $buildStatus == 8 || $buildStatus == 10 || $buildStatus == 11) {
        return "error";
    } else {
        return "failure";
    }
}

sub common {
    my ($self, $build, $dependents, $finished) = @_;
    my $cfg = $self->{config}->{githubstatus};
    my @config = defined $cfg ? ref $cfg eq "ARRAY" ? @$cfg : ($cfg) : ();
    my $baseurl = $self->{config}->{'base_uri'} || "http://localhost:3000";

    # Find matching configs
    foreach my $b ($build, @{$dependents}) {
        my $jobName = showJobName $b;
        my $evals = $build->jobsetevals;
        my $ua = LWP::UserAgent->new();

        foreach my $conf (@config) {
            next unless $jobName =~ /^$conf->{jobs}$/;

            my $contextTrailer = $conf->{excludeBuildFromContext} ? "" : (":" . $b->id);
            my $link = "$baseurl/build/" . $b->id;
            my $body = encode_json(
                {
                    body => "Hydra build #" . $b->id . " of $jobName:\n## " . ($finished ? toGithubState($b->buildstatus) : "pending") . "\n\n" .
                            "Build at [$link]($link)"
                });
            my $inputs_cfg = $conf->{inputs};
            my @inputs = defined $inputs_cfg ? ref $inputs_cfg eq "ARRAY" ? @$inputs_cfg : ($inputs_cfg) : ();
            my %seen = map { $_ => {} } @inputs;
            while (my $eval = $evals->next) {
                foreach my $input (@inputs) {
                    my $i = $eval->jobsetevalinputs->find({ name => $input, altnr => 0 });
                    next unless defined $i;
                    my $uri = $i->uri;
                    my $rev = $i->revision;
                    my $key = $uri . "-" . $rev;
                    next if exists $seen{$input}->{$key};
                    $seen{$input}->{$key} = 1;
                    $uri =~ m![:/]([^/]+)/([^/]+?)(?:.git)?$!;
                    my $req = HTTP::Request->new('POST', "https://api.github.com/repos/$1/$2/commits/$rev/comments");
                    $req->header('Content-Type' => 'application/json');
                    $req->header('Accept' => 'application/vnd.github.v3+json');
                    $req->header('Authorization' => $conf->{authorization});
                    $req->content($body);
                    print STDERR "DEBUG: github status req: ", Data::Dump::dump($req), "\n";
                    my $res = $ua->request($req);
                    print STDERR $res->status_line, ": ", $res->decoded_content, "\n" unless $res->is_success;
                }
            }
        }
    }
}

sub buildStarted {
    common(@_, [], 0);
}

sub buildFinished {
    common(@_, 1);
}

1;
