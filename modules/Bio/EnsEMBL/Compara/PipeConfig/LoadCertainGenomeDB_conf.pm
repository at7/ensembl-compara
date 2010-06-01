
=pod 

=head1 NAME

  Bio::EnsEMBL::Compara::PipeConfig::LoadCertainGenomeDB_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::LoadCertainGenomeDB_conf -password <your_password>

=head1 DESCRIPTION  

    This is a test of LoadOneGenomeDB.pm Runnable

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Compara::PipeConfig::LoadCertainGenomeDB_conf;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Compara::PipeConfig::ComparaGeneric_conf');

sub default_options {
    my ($self) = @_;
    return {
        %{$self->SUPER::default_options},

        'pipeline_name' => 'load_certain_genomedb',

        'pipeline_db' => {                                  # connection parameters
            -host   => 'compara2',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),                        # a rule where a previously undefined parameter is used (which makes either of them obligatory)
            -dbname => $ENV{USER}.'_'.$self->o('pipeline_name'),    # a rule where a previously defined parameter is used (which makes both of them optional)
        },

        'reg1' => {
            -host   => 'ens-staging',
            -port   => 3306,
            -user   => 'ensro',
            -pass   => '',
        },

        'reg2' => {
            -host   => 'ens-staging2',
            -port   => 3306,
            -user   => 'ensro',
            -pass   => '',
        },
        
        'reg3' => {
            -host   => 'ens-livemirror',
            -port   => 3306,
            -user   => 'ensro',
            -pass   => '',
        },
    };
}

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'load_genomedb',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::LoadOneGenomeDB',
            -parameters => {
                'registry_dbs' => [ $self->o('reg1'), $self->o('reg2'), $self->o('reg3') ],
            },
            -hive_capacity => 5,       # allow several workers to perform identical tasks in parallel
            -input_ids => [
                { 'gdb' =>  3, 'species_name' => 'Rattus norvegicus' },
                { 'gdb' => 57, 'species_name' => 'Mus musculus' },
                { 'gdb' => 90, 'species_name' => 'Homo sapiens' },
            ],
            -flow_into => {
                1 => [ 'dummy' ],   # each will flow into another one
            },
        },

        {   -logic_name    => 'dummy',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -hive_capacity => 10,       # allow several workers to perform identical tasks in parallel
        },
    ];
}

1;

