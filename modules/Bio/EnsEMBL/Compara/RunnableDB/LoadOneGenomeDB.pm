
=pod 

=head1 NAME

Bio::EnsEMBL::Compara::RunnableDB::LoadOneGenomeDB

=head1 DESCRIPTION

This Runnable loads one entry into 'genome_db' table and passes on the genome_db_id.

The format of the input_id follows the format of a Perl hash reference.
Examples:
    { 'species_name' => 'Homo sapiens', 'assembly_name' => 'GRCh37' }
    { 'species_name' => 'Mus musculus' }

supported keys:
    'locator'       => <string>
        one of the ways to specify the connection parameters to the core database (overrides 'species_name' and 'assembly_name')

    'registry_dbs'  => <list_of_dbconn_hashes>
        another, simple way to specify the genome_db (and let the registry search across multiple mysql instances to do the rest)
    'species_name'  => <string>
        mandatory, but what would you expect?

    'first_found'   => <0|1>
        optional, defaults to 0.
        Defines whether we emulate (to a certain extent) the behaviour of load_registry_from_multiple_dbs
        or try the last one that still fits (this would allow to try ens-staging[12] *first*, and only then check if ens-livemirror has is a suitable copy).

    'assembly_name' => <string>
        optional: in most cases it should be possible to find the species just by using 'species_name'

    'gdb'  => <integer>
        optional, in case you want to specify it (otherwise it will be generated by the adaptor when storing)

    'pseudo_stableID_prefix' => <string>
        optional?, see 'GenomeLoadMembers.pm', 'GenomeLoadReuseMembers.pm', 'GenomeLoadNCMembers.pm', 'GeneStoreNCMembers.pm', 'GenomePrepareNCMembers.pm'

    'ensembl_genomes' => <0|1>
        optional, sets the preferential order of precedence of species_name sources, depending on whether the module is run by EG or Compara

=cut

package Bio::EnsEMBL::Compara::RunnableDB::LoadOneGenomeDB;

use strict;
use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::DBLoader;
use Bio::EnsEMBL::Compara::GenomeDB;

use base ('Bio::EnsEMBL::Compara::RunnableDB::BaseRunnable');

sub Bio::EnsEMBL::DBSQL::DBAdaptor::extract_assembly_name {  # with much regret I have to introduce the highly demanded method this way
    my $self = shift @_;

    my ($cs) = @{$self->get_CoordSystemAdaptor->fetch_all()};
    my $assembly_name = $cs->version;

    return $assembly_name;
}

sub fetch_input {
    my $self = shift @_;

    my $assembly_name = $self->param('assembly_name');
    my $core_dba;

    if(my $locator = $self->param('locator') ) {   # use the locator and skip the registry

        eval {
            $core_dba = Bio::EnsEMBL::DBLoader->new($locator);

            $assembly_name ||= $core_dba->extract_assembly_name();
        };
        if($assembly_name and $self->param('assembly_name') and ($assembly_name ne $self->param('assembly_name')) ) {
            die "The required assembly_name '".$self->param('assembly_name')."' is different from the one found in the database: '$assembly_name', please investigate";
        }

    } elsif( my $species_name = $self->param('species_name') ) {    # perform (multi)registry search

=comment This part is not working yet, but hopefully with Ian's help we will be able to do something like this:

        foreach my $registry_db (@{ $self->param('registry_dbs') }) {
            # local %Bio::EnsEMBL::Registry::registry_register = ();
            # Bio::EnsEMBL::Registry->clear();
            # %Bio::EnsEMBL::Registry::registry_register = ();
            # $Bio::EnsEMBL::Registry::registry_register{'_ALIAS'} = {};

            Bio::EnsEMBL::Registry->load_registry_from_db( %$registry_db );

            my $this_core_dba = Bio::EnsEMBL::Registry->get_DBAdaptor($species_name, 'core') || next;

            $assembly_name ||= $this_core_dba->extract_assembly_name();

            if($this_assembly eq $assembly_name) {
                $core_dba = $this_core_dba;

                if($self->param('first_found')) {
                    last;
                }
            }

        } # try next registry server

=cut
            # In the meantime, try to get as much as we can from load_registry_from_multiple_dbs (assuming no clashes are allowed) :

        Bio::EnsEMBL::Registry->load_registry_from_multiple_dbs( @{ $self->param('registry_dbs') } );
        
        $core_dba = Bio::EnsEMBL::Registry->get_DBAdaptor($species_name, 'core');
        $assembly_name ||= $core_dba->extract_assembly_name();

        if($assembly_name and $self->param('assembly_name') and ($assembly_name ne $self->param('assembly_name')) ) {
            die "The required assembly_name '".$self->param('assembly_name')."' is different from the one found in the database: '$assembly_name', please investigate";
        }

    }

    if( $core_dba ) {
        $self->param('core_dba', $core_dba);
        $self->param('assembly_name', $assembly_name);
    } else {
        die "Could not find species_name='".$self->param('species_name')."', assembly_name='".$self->param('assembly_name')."' on the servers provided, please investigate";
    }
}

sub run {
    my $self = shift @_;

    my $species_name    = $self->param('species_name');
    my $assembly_name   = $self->param('assembly_name');
    my $core_dba        = $self->param('core_dba');
    my $genome_db_id    = $self->param('gdb')       || undef;
    my $meta_container  = $core_dba->get_MetaContainer;

    my $taxon_id        = $self->param('taxon_id')  || $meta_container->get_taxonomy_id;
    if($taxon_id != $meta_container->get_taxonomy_id) {
        die "taxon_id parameter ($taxon_id) is different from the one defined in the database (".$meta_container->get_taxonomy_id."), please investigate";
    }

    my $genebuild       = $meta_container->get_genebuild || '';

    my $ncbi_biname     = $self->compara_dba->get_NCBITaxonAdaptor->fetch_node_by_taxon_id($taxon_id);
    $ncbi_biname      &&= $ncbi_biname->binomial();
    my $meta_biname     = $meta_container->get_Species();
    $meta_biname      &&= $meta_biname->binomial();
    my $genome_name     = ( ($species_name ne $ncbi_biname) and $self->param('ensembl_genomes') and $species_name ) || $ncbi_biname || $species_name || $meta_biname
        || die "Could not figure out the genome_name, please investigate";

    my $locator         = $core_dba->dbc->locator;
    $locator .= ';species_id='.$core_dba->species_id if ($core_dba->species_id); # shouldn't it be a part of DBConnection::locator ?
    $locator .= ';disconnect_when_inactive=1';

    # ToDo: adapt the _get_name() subroutine from 'comparaLoadGenomes.pl'

    my $genome_db       = Bio::EnsEMBL::Compara::GenomeDB->new();
    $genome_db->dbID( $genome_db_id );
    $genome_db->taxon_id( $taxon_id );
    $genome_db->name( $genome_name );
    $genome_db->assembly( $assembly_name );
    $genome_db->genebuild( $genebuild );
    $genome_db->locator( $locator );

    $self->param('genome_db', $genome_db);
}

sub write_output {      # store the genome_db and dataflow
    my $self = shift;

    my $genome_db               = $self->param('genome_db');

    $self->compara_dba->get_GenomeDBAdaptor->store($genome_db);
    my $genome_db_id            = $genome_db->dbID();

    my $pseudo_stableID_prefix  = $self->param('pseudo_stableID_prefix');

    $self->dataflow_output_id( { 'gdb' => $genome_db_id, ($pseudo_stableID_prefix ? ('pseudo_stableID_prefix' => $pseudo_stableID_prefix) : ()) }, 1);
}

1;

