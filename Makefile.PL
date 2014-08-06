use 5.006;
use strict;
use warnings;

use ExtUtils::MakeMaker;

my(%params) =
(
	($] ge '5.005') ?
	(
		AUTHOR   => 'Nathaniel Lally <nll@cpan.org>',
		ABSTRACT => 'Subclass of Archive::Tar that deals with Android Backup files (adb backup / adb restore)',
	) : (),
	clean =>
	{
		FILES => 'blib/* Makefile MANIFEST AndoidBackup-*'
	},
	dist =>
	{
		COMPRESS => 'gzip',
		SUFFIX   => 'gz'
	},
	DISTNAME  => 'Archive-AndroidBackup',
	NAME      => 'Archive::AndroidBackup',
	PL_FILES  => {},
	PREREQ_PM =>
	{
		'constant'        => 0,
		'strict'          => 0,
		'Test::Version'   => 1.002003,
		'warnings'        => 0,
		'Moose'        => '2.0801',
		'MooseX::NonMoose'        => '0.26',
	},
	VERSION_FROM => 'lib/Archive/AndroidBackup.pm',
);

if ( ($ExtUtils::MakeMaker::VERSION =~ /^\d\.\d\d$/) && ($ExtUtils::MakeMaker::VERSION > 6.30) )
{
	$params{LICENSE} = 'artistic_2';
}

if ($ExtUtils::MakeMaker::VERSION ge '6.46')
{
	$params{META_MERGE} =
	{
		resources =>
		{
			bugtracker => 'https://rt.cpan.org/Public/Dist/Display.html?Name=Archive-AndroidBackup',
			license    => 'http://www.perlfoundation.org/artistic_license_2_0',
		},
	};
}

WriteMakefile(%params);
