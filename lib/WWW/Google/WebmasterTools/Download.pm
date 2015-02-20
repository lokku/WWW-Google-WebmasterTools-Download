package WWW::Google::WebmasterTools::Download;

use strict;
use warnings;

use namespace::autoclean;

use Moose;

use LWP::UserAgent;
use HTTP::Cookies;
use URI;

use XML::Twig;
use Text::CSV;
use JSON::MaybeXS;

use Path::Tiny;

my %ROOT_URIs = (
    LOGIN     => URI->new('https://www.google.com/accounts/ClientLogin'),
    SITES     => URI->new('https://www.google.com/webmasters/tools/feeds/sites/'),
    DOWNLOADS => URI->new('https://www.google.com/webmasters/tools/downloads-list'),
);

has 'email' => (
    is => 'ro',
    isa => 'Str'
);

has 'password' => (
    is => 'ro',
    isa => 'Str'
);

has 'language' => (
    is => 'ro',
    isa => 'Str',
    default => 'en',
);

has 'sites_regex' => (
    is => 'ro',
    isa => 'Regexp',
    default => sub { qr/./ },
);

has 'ua' => (
    is => 'ro',
    isa => 'LWP::UserAgent',
    default => sub {
        LWP::UserAgent->new(
            cookie_jar => HTTP::Cookies->new,
            agent      => 'WWW::Google::WebmasterTools::Download ',
        );
    },
);

has 'site_report_uri_cache' => (
    is => 'ro',
    isa => 'HashRef[URI]',
    default => sub { {} },
);

sub BUILD {
    my $self = shift;

    $self->_login;
    $self->_cache_download_uris;

    return;
}

sub _login {
    my $self = shift;

    my %post_data = (
        accountType => 'HOSTED_OR_GOOGLE',
        Email => $self->email,
        Passwd => $self->password,
        service => 'sitemaps',
        source => 'WWW::Google::WebmasterTools::Download',
    );

    my $response = $self->ua->post($ROOT_URIs{'LOGIN'}, \%post_data);

    if (!$response->is_success) {
        die sprintf(
            "Failed to log in as '%s': %s\n",
            $self->email,
            $response->status_line
        );
    }

    my $auth;
    if ($response->content =~ m{Auth=(.+)}msx) {
        $auth = $1;
    }
    else {
        die sprintf(
            "Failed to get auth token as '%s' from response content '%s'\n",
            $self->email,
            $response->content
        );
    }

    $self->ua->default_headers(
        HTTP::Headers->new(
            'Authorization' => sprintf('GoogleLogin auth=%s', $auth),
            'GData-Version' => 2,
        )
    );

    return;
}

sub _cache_download_uris {
    my $self = shift;

    my $site_report_uri_cache = $self->site_report_uri_cache;

    my @sites = $self->get_sites;

    SITE:
    for my $site (@sites) {
        my $site_download_list_uri = $ROOT_URIs{'DOWNLOADS'}->clone;
        $site_download_list_uri->query_form(
            hl => $self->language,
            siteUrl => $site
        );

        my $response = $self->ua->get($site_download_list_uri);
        if (!$response->is_success) {
            warn sprintf(
                "Failed to get download uris for site '%s': %s\n",
                $site,
                $response->status_line
            );
            next SITE;
        }

        my $json = $response->content;
        my $data = decode_json($json);

        for my $report (keys %$data) {
            my $URI = URI->new('https://www.google.com' . $data->{$report});
            $site_report_uri_cache->{$site}{$report} = $URI;
            $URI->query_form(
                $URI->query_form,
                prop => 'ALL',
                more => 'true',
            );
        }
    }

    return;
}

sub get_sites {
    my $self = shift;

    my $response = $self->ua->get($ROOT_URIs{'SITES'});

    if (!$response->is_success) {
        die sprintf(
            "Failed to get sites as '%s': %s\n",
            $self->email,
            $response->status_line
        );
    }

    my @sites;

    my $twig = XML::Twig->new(
        twig_handlers => {
            '/feed/entry/title' => sub { push @sites, $_->text_only }
        },
    );
    $twig->parse($response->content);

    return sort grep { $_ =~ $self->sites_regex } @sites;
}

sub get_top_pages_data        { shift->_get_json_data(@_, report => 'TOP_PAGES')        }
sub get_top_queries_data      { shift->_get_json_data(@_, report => 'TOP_QUERIES')      }
sub get_crawl_errors_data     { shift->_get_json_data(@_, report => 'CRAWL_ERRORS')     }
sub get_content_errors_data   { shift->_get_json_data(@_, report => 'CONTENT_ERRORS')   }
sub get_content_keywords_data { shift->_get_json_data(@_, report => 'CONTENT_KEYWORDS') }
sub get_latest_backlinks_data { shift->_get_json_data(@_, report => 'LATEST_BACKLINKS') }
sub get_internal_links_data   { shift->_get_json_data(@_, report => 'INTERNAL_LINKS')   }
sub get_external_links_data   { shift->_get_json_data(@_, report => 'EXTERNAL_LINKS')   }
sub get_social_activity_data  { shift->_get_json_data(@_, report => 'SOCIAL_ACTIVITY')  }

sub save_top_pages_as_csv        { shift->_save_csv_data(@_, report => 'TOP_PAGES')        }
sub save_top_queries_as_csv      { shift->_save_csv_data(@_, report => 'TOP_QUERIES')      }
sub save_crawl_errors_as_csv     { shift->_save_csv_data(@_, report => 'CRAWL_ERRORS')     }
sub save_content_errors_as_csv   { shift->_save_csv_data(@_, report => 'CONTENT_ERRORS')   }
sub save_content_keywords_as_csv { shift->_save_csv_data(@_, report => 'CONTENT_KEYWORDS') }
sub save_latest_backlinks_as_csv { shift->_save_csv_data(@_, report => 'LATEST_BACKLINKS') }
sub save_internal_links_as_csv   { shift->_save_csv_data(@_, report => 'INTERNAL_LINKS')   }
sub save_external_links_as_csv   { shift->_save_csv_data(@_, report => 'EXTERNAL_LINKS')   }
sub save_social_activity_as_csv  { shift->_save_csv_data(@_, report => 'SOCIAL_ACTIVITY')  }

sub _get_csv_data {
    my $self = shift;
    my %params = @_;

    my $website = $params{'website'} // die "Missing required parameter 'website'";
    my $report  = $params{'report'}  // die "Missing required parameter 'report'";

    my $uri = $self->site_report_uri_cache->{$website}{$report};
    if (!$uri) {
        die sprintf(
            "Don't know the URL for site '%s' report '%s'\n",
            $website,
            $report
        );
    }

    my $response = $self->ua->get($uri);

    if (!$response->is_success) {
        die sprintf(
            "Failed to get data for site '%s' report '%s': %s\n",
            $website, $report,
            $response->status_line
        );
    }

    return $response->content;
}

sub _save_csv_data {
    my $self = shift;
    my %params = @_;

    my $filename = delete $params{'filename'} // die "Missing required parameter 'filename'";

    my $csv_data = $self->_get_csv_data(%params);

    my $path = path($filename);
    $path->spew($csv_data);

    return;
}

sub _get_json_data {
    my $self = shift;

    my $csv_data = $self->_get_csv_data(@_);

    my $csv_parser = Text::CSV->new({ binary => 1 });
    my @csv_content = split /\n/, $csv_data;

    my @data;
    for my $line (@csv_content) {
        $csv_parser->parse($line);
        push @data, [ $csv_parser->fields ];
    }

    return @data;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

WWW::Google::WebmasterTools::Download - Extract data from Google Webmaster Tools

=head1 DESCRIPTION

This distribution is a rip-off of Stephan Schmitz's
php-webmaster-tools-downloads library which can be found on Github at
L<https://github.com/eyecatchup/php-webmaster-tools-downloads>.

This project provides an easy way to automate downloading of data tables from
Google Webmaster Tools and storing the results in CSV files.

It performs these actions essentially by scraping Google Webmaster Tools,
because the GWT API does not provide full access to all the data desired.

It is necessary because GWT only shows you data for the last three months, so
if you want to track your website for longer than that you have to store the
data separately yourself.

=head1 SYNOPSIS

    use WWW::Google::WebmasterTools::Download;

    my $gdata = WWW::Google::WebmasterTools::Download->new(
        email    => 'example@gmail.com',
        password => 'correct horse battery staple',
    );

    my @data = $gdata->get_content_keywords_data(
        website    => 'http://www.example.org',
    );

    $gdata->save_top_queries_as_csv(
        website    => 'http://www.example.org',
        filename   => 'content_keywords_data.csv'
    );

=head1 CONSTRUCTOR

=head2 new

Takes an email and password and returns an object with methods to access data
from Google Webmaster Tools.

    my $gdata = WWW::Google::WebmasterTools::Download->new(
        email    => 'example@gmail.com',
        password => 'correct horse battery staple',
    );

Immediately logs in and pre-caches all your site URLs which can be slow if you
have a large number of them or a slow internet connection.

Optionally takes a regular expression for filtering on which sites you are
interested in; a language (ISO 639-1 2-letter language code); and a user agent.

    my $gdata = WWW::Google::WebmasterTools::Download->new(
        email       => 'example@gmail.com',
        password    => 'correct horse battery staple',

        sites_regex => qr/example/,
        language    => 'de',
        ua          => LWP::UserAgent->new(agent => "My Agent Name"),
    );

The default sites regex matches all sites, the default language is 'en', and
the default user agent has the UserAgent string WWW::Google::WebmasterTools::Download.


=head1 SITE METHODS

=head2 get_sites

Returns a list of sites available for the user. Obeys the sites_regex parameter
passed to new().

    my @sites = $gdata->get_sites;

=head1 DATA METHODS

Each of these takes a website and returns an array of arrayrefs representing a
table of data.

    my @data = $gdata->get_top_pages_data(
        website => 'http://www.example.org'
    );

=head2 get_top_pages_data

=head2 get_top_queries_data

=head2 get_crawl_errors_data

=head2 get_content_errors_data

=head2 get_content_keywords_data

=head2 get_latest_backlinks_data

=head2 get_internal_links_data

=head2 get_external_links_data

=head2 get_social_activity_data

=head1 CSV METHODS

Each of these takes a website and a filename and writes a CSV file with the
data for that website.

    $gdata->save_top_queries_as_csv(
        website  => 'http://www.example.org',
        filename => 'example_org_top_queries.csv',
    );

=head2 save_top_pages_as_csv

=head2 save_top_queries_as_csv

=head2 save_crawl_errors_as_csv

=head2 save_content_errors_as_csv

=head2 save_content_keywords_as_csv

=head2 save_latest_backlinks_as_csv

=head2 save_internal_links_as_csv

=head2 save_external_links_as_csv

=head2 save_social_activity_as_csv

=cut
