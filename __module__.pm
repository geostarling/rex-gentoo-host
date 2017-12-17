package Rex::Gentoo::Host;

use Rex -base;
use Rex::Template::TT;
use Rex::Gentoo::Utils;

desc 'Setup Gentoo host system';

include qw/
Rex::Gentoo::Kernel
Rex::Gentoo::Networking
Rex::Bootloader::Syslinux
/;


task 'setup', sub {

  setup_users();
  setup_hostname();
  setup_hosts();
  setup_timezone();
  setup_portage();
  setup_locales();
  setup_packages();

};

task 'setup_portage', sub {
  file "/etc/portage/make.conf",
    content => template("templates/etc/portage/make.conf.tt");

  my @dirs = ("package.use", "package.mask", "package.accept_keywords");
  foreach my $dir (@dirs) {
    if( is_dir("/etc/portage/$dir") ) {
      file "/etc/portage/$dir", ensure => "absent";
    }
  }
  file "/etc/portage/package.use",
    content => template("templates/etc/portage/package.use.tt");
  file "/etc/portage/package.accept_keywords",
    content => template("templates/etc/portage/package.accept_keywords.tt");
  file "/etc/portage/package.mask",
    content => template("templates/etc/portage/package.mask.tt");
};

task 'setup_portage_world', sub {
  my $pkgs = param_lookup('packages');

  file "/etc/portage/world",
    ensure => "present";

  foreach my $pkg (keys %$pkgs) {
    append_if_no_such_line "/etc/portage/world",
      line  => $pkg,
      regexp => qr/^$pkg/;
  }
};

task 'setup_packages', sub {

  setup_portage();

  setup_portage_world();

  if( !is_symlink("/var/lib/portage/world") ) {
    file "/var/lib/portage/world",
      ensure => "absent";
  }

  symlink("/etc/portage/world", "/var/lib/portage/world");

  # sync portage tree
  Rex::Gentoo::Utils::optional(sub { update_package_db; }, 'Do you want to sync the Portage tree?');

  # update all installed packages (@world) to their latest versions
  Rex::Gentoo::Utils::optional(sub { update_system; }, 'Do you want to update @world packages?');

};


task 'setup_services', sub {
    my $services = param_lookup('services');
    foreach my $svc (keys %$services) {
        service $svc, ensure => "enabled";
        service $svc, ensure => "started";
    }
};

task 'setup_hostname', sub {
  my $hostname = param_lookup('hostname', 'localhost');
  file '/etc/conf.d/hostname',
    content => "hostname=\"$hostname\"",
    on_change => sub { service 'hostname' => 'restart' };
};

task 'setup_hosts', sub {
  $DB::single = 1;
  my $hostname = param_lookup('hostname', 'localhost');
  my $domainname = param_lookup('domainname');
  my $hosts = param_lookup('hosts_file', []);
  file '/etc/hosts',
    content => template("templates/etc/hosts.tt",
                        hostname => $hostname,
                        domainname => $domainname,
                        hosts => $hosts);
};

task 'setup_timezone', sub {
  file '/etc/timezone',
    content => param_lookup('timezone', 'Etc/UTC'),
    on_change => sub { run 'emerge --config sys-libs/timezone-data'; };
};

task 'setup_locales', sub {
  file '/etc/locale.gen',
    content => join("\n", @{param_lookup('locales', ['en_US.UTF-8 UTF-8'])}),
    on_change => sub { run 'locale-gen'; };

  Rex::Gentoo::Utils::_eselect("locale", "system_locale", "en_US.utf8");
};

task 'setup_kernel', sub {
  Rex::Gentoo::Utils::optional(\&Rex::Gentoo::Kernel::setup, "Do you want to (re)compile the kernel?");
};

task 'setup_users', sub {
  my $users = param_lookup 'users', [];
  foreach $user (@$users) {
    if ($user->{name} ne 'root') {
      account $user->{name},
        ensure         => "present",
        comment        => $user->{name},
        groups         => $user->{groups},
        password       => $user->{password},
        crypt_password => $user->{crypt_password};
    }
    setup_ssh_keys(user => $user->{name});
  }
};


task 'setup_ssh_keys', sub {
    my $params = shift;
    my $users = param_lookup 'users', [];
    my @filtered_users;
    if ( exists $params->{user} ) {
        @filtered_users = grep { $_->{name} == $params->{user} } @$users;
    } else {
        @filtered_users = @$users;
    }

    foreach $user (@filtered_users) {
        my $keys = $user->{ssh_keys};
        my $home =  run "getent passwd " . $user->{name} . " | cut -d: -f6", autodie => TRUE;
        my $authz_keys_file = "$home/.ssh/authorized_keys";

        file "$home/.ssh/", ensure => "directory";
        file $authz_keys_file, ensure => "present";
        foreach my $key (@{$user->{ssh_keys}}) {
            my $comment = $key->{comment};
            append_or_amend_line $authz_keys_file,
            line  => $key->{key} . " " . $comment,
            regexp => qr{^ssh-rsa [^ ]+ $comment$};
        }
    }
};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Rex::Gentoo::Install/;

 task yourtask => sub {
    Rex::Gentoo::Install::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
