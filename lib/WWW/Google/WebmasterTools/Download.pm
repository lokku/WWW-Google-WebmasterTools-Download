package WWW::Google::WebmasterTools::Download;

use strict;
use warnings;

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

    my $data = $gdata->get_content_keywords_data(
        website    => 'http://www.example.org',
        date_range => [ '2015-02-14', '2015-02-18' ],
    );

    $gdata->save_top_queries_as_csv(
        website    => 'http://www.example.org',
        filename   => 'content_keywords_data.csv'
        date_range => [ '2015-02-14', '2015-02-18' ],
    );

=head1 CONSTRUCTOR

=head2 new

=head1 DATA METHODS

Each of these takes a website and returns an array of arrayrefs representing a
table of data.

    my $data = $gdata->get_top_pages_data(
        website => 'http://www.example.org'
    );

Optionally takes a date range, which is an arrayref of exactly dates in
YYYY-MM-DD format. If this is not passed then the default is the last three
months.

    my $data = $gdata->get_top_pages_data(
        website    => 'http://www.example.org',
        date_range => [ '2015-02-14', '2015-02-18' ],
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

Optionally takes a date range, which is an arrayref of exactly dates in
YYYY-MM-DD format. If this is not passed then the default is the last three
months.

    my $data = $gdata->save_top_queries_as_csv(
        website    => 'http://www.example.org',
        filename => 'example_org_top_queries.csv',
        date_range => [ '2015-02-14', '2015-02-18' ],
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
