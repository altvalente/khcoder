package kh_cod::asso;
use base qw(kh_cod);
use strict;

my %sql_join = (
	'bun' =>
		'bun.id = hyosobun.bun_idt',
	'dan' =>
		'
			    dan.dan_id = hyosobun.dan_id
			AND dan.h5_id = hyosobun.h5_id
			AND dan.h4_id = hyosobun.h4_id
			AND dan.h3_id = hyosobun.h3_id
			AND dan.h2_id = hyosobun.h2_id
			AND dan.h1_id = hyosobun.h1_id
		',
	'h5' =>
		'
			    h5.h5_id = hyosobun.h5_id
			AND h5.h4_id = hyosobun.h4_id
			AND h5.h3_id = hyosobun.h3_id
			AND h5.h2_id = hyosobun.h2_id
			AND h5.h1_id = hyosobun.h1_id
		',
	'h4' =>
		'
			    h4.h4_id = hyosobun.h4_id
			AND h4.h3_id = hyosobun.h3_id
			AND h4.h2_id = hyosobun.h2_id
			AND h4.h1_id = hyosobun.h1_id
		',
	'h3' =>
		'
			    h3.h3_id = hyosobun.h3_id
			AND h3.h2_id = hyosobun.h2_id
			AND h3.h1_id = hyosobun.h1_id
		',
	'h2' =>
		'
			    h2.h2_id = hyosobun.h2_id
			AND h2.h1_id = hyosobun.h1_id
		',
	'h1' =>
		'h1.h1_id = hyosobun.h1_id',
);

sub new{
	my $class = shift;
	my $self;
	$self->{dummy} = '0';
	
	bless $self, $class;
	
	return $self;
}

#------------------------------#
#   直接入力コードの読み込み   #
#------------------------------#

sub add_direct{
	my $self = shift;
	my %args = @_;
	
	# 既に追加されていた場合はいったん削除
	if ($self->{codes}){
		if ($self->{codes}[0]->name eq '＃直接入力'){
			print "Deleting old \'direct\' code\n";
			shift @{$self->{codes}};
		}
	}
	
	if ($args{mode} eq 'code'){                   #「code」の場合
		unshift @{$self->{codes}}, kh_cod::a_code->new(
			'＃直接入力',
			Jcode->new($args{raw})->euc
		);
	} else {                                      # 「AND」,「OR」の場合
		$args{raw} = Jcode->new($args{raw})->tr('　',' ')->euc;
		$args{raw} =~ tr/\t\n/  /;
		my ($n, $t) = (0,'');
		foreach my $i (split / /, $args{raw}){
			unless ( length($i) ){next;}
			if ($n){$t .= " $args{mode} ";}
			$t .= "$i";
			++$n;
		}
		unshift @{$self->{codes}}, kh_cod::a_code->new(
			'＃直接入力',
			$t
		);
	}
}

#----------------#
#   計算の実行   #
#----------------#

sub asso{
	my $self = shift;
	my %args = @_;
	
	$self->{tani} = $args{tani};
	$self->{last_search_words} = undef;

	#--------------------#
	#   文書検索の実行   #

	print "1: coding...\n";

	# 「＃コード無し」の使われ方をチェック
	my $code_num_check = @{$self->{codes}};
	my $no_code_flag = 0;
	foreach my $i (@{$args{selected}}){
		if ($i == $code_num_check){
			print "\    'no code\' selected\n";
			$no_code_flag = 1;
			last;
		}
	}
	if ($no_code_flag){
		unless (
			   (@{$args{selected}} == 1 )
			|| (
					   (@{$args{selected}} == 2)
					&& ($args{selected}->[0] == 0 )
			   )
		){
			print "    error: illegal use of \'no code\'\n";
			return undef;
		};
	}
	
	# コーディング
	if ($no_code_flag){                 # 全てのコード
		if ($self->{codes}){
			foreach my $i (@{$self->{codes}}){
				$i->clear;
			}
		}
		$self->code($self->{tani}) or return 0;
	} else {                            # 選択されたコードのみ
		foreach my $i (@{$args{selected}}){
			$self->{codes}[$i]->clear;
			$self->{codes}[$i]->ready($args{tani});
			$self->{codes}[$i]->code("ct_$args{tani}_ascode_"."$i");
			if ($self->{codes}[$i]->res_table){
				push @{$self->{valid_codes}}, $self->{codes}[$i]; 
			}
		}
	}

	# AND条件の時に、0コードが存在した場合はreturn
	unless ($self->{valid_codes}){
		return undef;
	}
	if (
		   ( $args{method} eq 'and' )
		&& ( @{$self->{valid_codes}} < @{$args{selected}} )
	) {
		return undef;
	}

	# 合致する文書のリストを作成
	mysql_exec->drop_table("temp_word_ass");    # テーブルの準備
	mysql_exec->do("
		create temporary table temp_word_ass(
			id int not null primary key
		) TYPE=HEAP
	",1);

	my $sql;                                    # リストをテーブルに投入
	$sql .= "INSERT INTO temp_word_ass (id)\n";
			# 「コード無し」を使用している場合
	if ($no_code_flag){
		$sql .= "SELECT $args{tani}.id\nFROM $args{tani}\n";
		my $n = 0;
		foreach my $i (@{$self->{codes}}){
			if ($n == 0 && @{$args{selected}} == 1 ){$n = 1; next;}
			unless ($i->res_table){next;}
			$sql .=
				"LEFT JOIN "
				.$i->res_table
				." ON $args{tani}.id = "
				.$i->res_table
				.".id\n";
			++$n;
		}
		
		$sql .= "WHERE\n";
		if (@{$args{selected}} == 2){
			$sql .=
				"IFNULL("
				.$self->{codes}[0]->res_table
				."."
				.$self->{codes}[0]->res_col
				.",0)\n AND ";
		}
		$sql .= "NOT (\n";
		$n = 0;
		foreach my $i (@{$self->{codes}}){
			unless  ($n){$n = 1; next;}
			unless ($i->res_table){next;}
			$sql .= " OR " if ($n > 1);
			$sql .=
				"IFNULL("
				.$i->res_table
				."."
				.$i->res_col
				.",0)\n";
			++$n;
		}
		$sql .= ")";
	}
	
			# 「コード無し」を使用しない場合
	else {
		$sql .= "SELECT $args{tani}.id\n";
		$sql .= "FROM $args{tani}\n";
		
		foreach my $i (@{$args{selected}}){
			unless ($self->{codes}[$i]->res_table){
				next;
			}
			$sql .=
				"LEFT JOIN "
				.$self->{codes}[$i]->res_table
				." ON $args{tani}.id = "
				.$self->{codes}[$i]->res_table
				.".id\n";
		}
		$sql .= "WHERE\n";
		my $n = 0;
		foreach my $i (@{$args{selected}}){
			if ($n){ $sql .= "$args{method} "; }
			if ($self->{codes}[$i]->res_table){
				$sql .=
					"IFNULL("
					.$self->{codes}[$i]->res_table
					."."
					.$self->{codes}[$i]->res_col
					.",0)\n";
			} else {
				$sql .= "0\n";
			}
			++$n;
		}
	}
	mysql_exec->do($sql,1);

	#------------------------#
	#   条件付き確立の計算   #
	my $m_table = 'temp_word_ass';
	my $tani    = $args{tani};
	
	print "2: conditional probability...\n";
	
	my $denom1 = mysql_exec->select("SELECT count(*) from $m_table",1)
		->hundle->fetch->[0];                     # 条件付き確立の分母
	unless ($denom1){return 0;}
	mysql_exec->drop_table("ct_ass_p");           # 条件付き確立保存テーブル
	mysql_exec->do("
		CREATE TEMPORARY TABLE ct_ass_p(
			genkei_id INT primary key,
			p         INT
		) TYPE=HEAP
	",1);
	$sql = "INSERT INTO ct_ass_p (genkei_id, p)\n";
	$sql .= "SELECT genkei.id, COUNT(DISTINCT $tani.id)\n";
	$sql .= "FROM hyosobun, $tani, $m_table, hyoso, genkei, hselection\n";
	$sql .= "WHERE\n$sql_join{$tani}";
	$sql .= "\tAND hyosobun.hyoso_id = hyoso.id\n";
	$sql .= "\tAND hyoso.genkei_id = genkei.id\n";
	$sql .= "\tAND genkei.nouse = 0\n";
	$sql .= "\tAND hselection.khhinshi_id = genkei.khhinshi_id\n";
	$sql .= "\tAND hselection.ifuse = 1\n";
	$sql .= "\tAND $m_table.id = $tani.id\n";
	$sql .= "GROUP BY genkei.id";
	mysql_exec->do($sql,1);

	print "3: delete unnecessary words...\n";
	my (@words, %words);                          # 表層リストを取得
	foreach my $i (@{$args{selected}}){
		unless ($self->{codes}[$i]){next;}
		unless ($self->{codes}[$i]->res_table){
			next;
		}
		if ($self->{codes}[$i]->hyosos){
			foreach my $h (@{$self->{codes}[$i]->hyosos}){
				++$words{$h};
			}
		}
	}
	@words = (keys %words);                       # 表層リストを基本形リストに
	$sql =  "SELECT genkei.id\n";                 #                       変換
	$sql .= "FROM genkei, hyoso\n";
	$sql .= "WHERE\n";
	$sql .= "\tgenkei.id = hyoso.genkei_id\n";
	$sql .= "\tAND (\n";
	my $n = 0;
	foreach my $i (@words){
		if ($n){ $sql .= "OR "; }
		$sql .= "hyoso.id = $i\n";
		++$n;
	}
	$sql .= "\t)\n";
	$sql .= "GROUP BY genkei.id";
	my $h = mysql_exec->select("$sql",1)->hundle;
	@words = ();
	while (my $i = $h->fetch){
		push @words, $i->[0];
	}
	$sql = "DELETE FROM ct_ass_p\n";
	$sql .= "WHERE\n";
	$n = 0;
	foreach my $i (@words){
		if ($n){ $sql .= "OR ";}
		$sql .= "genkei_id = $i\n";
		++$n;
	}
	mysql_exec->do($sql,1);

	print "4: probability...\n";

	my $denom2 = mysql_exec->select("SELECT count(*) from $tani",1)
		->hundle->fetch->[0];                     # 全体確立の分母
	mysql_exec->drop_table("ct_ass_a");           # 全体確立保存テーブル
	mysql_exec->do("
		CREATE TABLE ct_ass_a(
			genkei_id INT primary key,
			p         INT
		) TYPE=HEAP
	",1);
	$sql = "INSERT INTO ct_ass_a (genkei_id, p)\n";
	$sql .= "SELECT genkei.id, COUNT(DISTINCT $tani.id)\n";
	$sql .= "FROM hyosobun, $tani, ct_ass_p, hyoso, genkei\n";
	$sql .= "WHERE\n$sql_join{$tani}";
	$sql .= "\tAND hyosobun.hyoso_id = hyoso.id\n";
	$sql .= "\tAND hyoso.genkei_id = genkei.id\n";
	$sql .= "\tAND ct_ass_p.genkei_id = genkei.id\n";
	$sql .= "GROUP BY genkei.id";
	mysql_exec->do($sql,1);

	print "done\n";
}

#--------------------#
#   結果の取り出し   #
#--------------------#
sub fetch_results{
	my $self = shift;

	my $denom1 = mysql_exec->select("SELECT count(*) from temp_word_ass",1)
		->hundle->fetch->[0];                     # 条件付き確立の分母
	my $denom2 = mysql_exec->select("SELECT count(*) from $self->{tani}",1)
		->hundle->fetch->[0];                     # 全体確立の分母

	$self->{doc_num} = $denom1;

	my $sql ="
		SELECT
			genkei.name,
			khhinshi.name,
			ct_ass_a.p,
			ROUND(ct_ass_a.p / $denom2, 3),
			ct_ass_p.p,
			ROUND(ct_ass_p.p / $denom1, 3),
			ROUND(ct_ass_p.p / $denom1 - ct_ass_a.p / $denom2, 15) as lift
		FROM genkei, khhinshi, ct_ass_p, ct_ass_a
		WHERE
			    genkei.khhinshi_id = khhinshi.id
			AND ct_ass_p.genkei_id = ct_ass_a.genkei_id
			AND ct_ass_p.genkei_id = genkei.id
		ORDER BY lift DESC
		LIMIT 200
	";

	return mysql_exec->select($sql)->hundle->fetchall_arrayref;

}


sub doc_num{
	my $self = shift;
	return $self->{doc_num};
}

1;