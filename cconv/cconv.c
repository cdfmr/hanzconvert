/*
 * Copyright (C) 2008, 2009
 * Free Software Foundation, Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * \author Yang Jianyu <xiaoyjy@hotmail.com>
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <time.h>
#include <errno.h>

#include "cconv.h"
#include "cconv_table.h"
#include "unicode.h"

#ifdef HAVE_CONFIG_H
	#include "config.h"
#endif

typedef struct cconv_struct
{
	cconv_type cconv_cd;
	iconv_t    iconv_cd;
	iconv_t    gb_utf8;
	iconv_t    bg_utf8;
	iconv_t    utf8_gb;
	iconv_t    utf8_bg;
	int        size_factor;
	char       options[16];
}
cconv_struct;

static size_t cconv_utf8(
	const char** inbuf,
	size_t* inleft    ,
	char**  outbuf    ,
	size_t* outleft   ,
	const language_zh_map *m,
	int map_size
);

static int find_keyword(
	const char* inbytes  ,
	size_t*     length   ,
	size_t		max_length,
	const language_zh_map *m   ,
	int         begin    ,
	int         end      ,
	const int   whence
);

static int binary_find(
	const char* inbytes  ,
	size_t*     length   ,
	size_t		max_length,
	const language_zh_map *m   ,
	int         begin    ,
	int         end
);

static int match_cond(
	const factor_zh_map* cond   ,
	const char*          str    ,
	int                  klen   ,
	const int            whence
);

static int match_real_cond(
	const char* mc   ,
	const char* str  ,
	int         head ,
	const int   whence
);

/* {{{ cconv_t cconv_open(const char* tocode, const char* fromcode) */
/**
 * Open a cconv handle.
 *
 * @param   tocode	Convert to-code.
 * @param   fromcode	Convert from-code.
 * @retval  t_handle	Cconv handle,(-1: error).
 */
cconv_t cconv_open(const char* tocode, const char* fromcode)
{
	char code[8] = {0, };
	char *ptr;
	cconv_struct* cd = (cconv_struct*)malloc(sizeof(cconv_struct));
	cd->cconv_cd = CCONV_NULL;
	cd->iconv_cd = NULL;
	cd->gb_utf8  = NULL;
	cd->bg_utf8  = NULL;
	cd->utf8_gb  = NULL;
	cd->utf8_bg  = NULL;
	cd->size_factor = 4;

	/* //IGNORE //TRANSPORT etc. */
	if((ptr = strstr(fromcode, "//")) != NULL)
	{
		strncpy(cd->options, ptr     , 16);
		strncpy(code       , fromcode, ptr - fromcode);
		fromcode = code;
	}

	if(0 == strcasecmp(CCONV_CODE_GBL, fromcode))
	{
		cd->gb_utf8 = iconv_open(CCONV_CODE_UTF, CCONV_CODE_GBL);
		if(0 == strcasecmp(CCONV_CODE_UHT, tocode) || 0 == strcasecmp(CCONV_CODE_UHK, tocode)
				||0 == strcasecmp(CCONV_CODE_UTW, tocode))
		{
			cd->cconv_cd = CCONV_GBL_TO_UHT;
		}
		else if(0 == strcasecmp(CCONV_CODE_UHS, tocode) || 0 == strcasecmp(CCONV_CODE_UCN, tocode))
			cd->cconv_cd = CCONV_GBL_TO_UHS;
		else if(0 == strcasecmp(CCONV_CODE_BIG, tocode))
		{
			cd->cconv_cd = CCONV_GBL_TO_BIG;
			cd->utf8_bg  = iconv_open(CCONV_CODE_BIG, CCONV_CODE_UTF);
		}
		else if(0 == strcasecmp(CCONV_CODE_GHS, tocode))
		{
			cd->cconv_cd = CCONV_GBL_TO_GHS;
			cd->utf8_gb  = iconv_open(CCONV_CODE_GBL, CCONV_CODE_UTF);
		}
		else if(0 == strcasecmp(CCONV_CODE_GHT, tocode))
		{
			cd->cconv_cd = CCONV_GBL_TO_GHT;
			cd->utf8_gb  = iconv_open(CCONV_CODE_GBL, CCONV_CODE_UTF);
		}
	}
	else
	if(0 == strcasecmp(CCONV_CODE_UTF, fromcode)
	 ||0 == strcasecmp(CCONV_CODE_UHS, fromcode)
	 ||0 == strcasecmp(CCONV_CODE_UHT, fromcode)
	 ||0 == strcasecmp(CCONV_CODE_UCN, fromcode)
	 ||0 == strcasecmp(CCONV_CODE_UHK, fromcode)
	 ||0 == strcasecmp(CCONV_CODE_UTW, fromcode)
	) {
		if(0 == strcasecmp(CCONV_CODE_UHS, tocode) || 0 == strcasecmp(CCONV_CODE_UCN, tocode))
			cd->cconv_cd = CCONV_UTF_TO_UHS;
		else if(0 == strcasecmp(CCONV_CODE_UHT, tocode) || 0 == strcasecmp(CCONV_CODE_UHK, tocode)
		     || 0 == strcasecmp(CCONV_CODE_UTW, tocode))
			cd->cconv_cd = CCONV_UTF_TO_UHT;
		else if(0 == strcasecmp(CCONV_CODE_GBL, tocode) || 0 == strcasecmp(CCONV_CODE_GHS, tocode))
		{
			cd->cconv_cd = CCONV_UTF_TO_GBL;
			cd->utf8_gb  = iconv_open(CCONV_CODE_GBL, CCONV_CODE_UTF);
		}
		else if(0 == strcasecmp(CCONV_CODE_GHT, tocode))
		{
			cd->cconv_cd = CCONV_UTF_TO_GHT;
			cd->utf8_gb  = iconv_open(CCONV_CODE_GBL, CCONV_CODE_UTF);
		}
		else if(0 == strcasecmp(CCONV_CODE_BIG, tocode))
		{
			cd->cconv_cd = CCONV_UTF_TO_BIG;
			cd->utf8_bg  = iconv_open(CCONV_CODE_BIG, CCONV_CODE_UTF);
		}

		cd->size_factor = 1;
	}
	else
	if(0 == strcasecmp(CCONV_CODE_BIG, fromcode))
	{
		if(0 == strcasecmp(CCONV_CODE_GBL, tocode) || 0 == strcasecmp(CCONV_CODE_GHS, tocode))
		{
			cd->cconv_cd = CCONV_BIG_TO_GBL;
			cd->bg_utf8  = iconv_open(CCONV_CODE_UTF, CCONV_CODE_BIG);
			cd->utf8_gb  = iconv_open(CCONV_CODE_GBL, CCONV_CODE_UTF);
		}
		else if(0 == strcasecmp(CCONV_CODE_UHS, tocode) || 0 == strcasecmp(CCONV_CODE_UCN, tocode))
		{
			cd->cconv_cd = CCONV_BIG_TO_UHS;
			cd->bg_utf8  = iconv_open(CCONV_CODE_UTF, CCONV_CODE_BIG);
		}

		/* just use iconv to do others. */
	}

	if(cd->cconv_cd == CCONV_NULL)
		cd->iconv_cd = iconv_open(tocode, fromcode);

	if( cd->iconv_cd == (iconv_t)(-1) || cd->gb_utf8  == (iconv_t)(-1)
	 || cd->bg_utf8  == (iconv_t)(-1) || cd->utf8_gb  == (iconv_t)(-1)
	 || cd->utf8_bg  == (iconv_t)(-1)) {
		cconv_close(cd);
		return (cconv_t)(CCONV_ERROR);
	}

	return cd;
}
/* }}} */

size_t iconv_wrapper(iconv_t cd,  char* * inbuf, size_t *inbytesleft, char* * outbuf, size_t *outbytesleft)
{
	size_t res = iconv(cd, inbuf, inbytesleft, outbuf, outbytesleft);
	if (res != (size_t)(-1))
		return res;

	return errno == EINVAL ? 0 : res;
}

#define cconv_iconv_first(cd) \
	ps_outbuf = ps_midbuf = (char*)malloc(o_proc); \
	iconvctl(cd, ICONV_SET_DISCARD_ILSEQ, &one); \
	if(iconv_wrapper(cd, inbuf, inbytesleft, &ps_outbuf, &o_proc) == -1) { \
		free(ps_midbuf); return (size_t)(-1); \
	} \

#define cconv_cconv_second(n, o) \
	cd_struct->cconv_cd = n; \
	ps_inbuf = ps_midbuf; \
	o_proc   = m_proc - o_proc; \
	if((i_proc = cconv(cd, &ps_inbuf, &o_proc, outbuf, outbytesleft)) == -1) { \
		free(ps_midbuf); return (size_t)(-1); \
	} \
	free(ps_midbuf); \
	cd_struct->cconv_cd = o; \
	return i_proc;

#define cconv_cconv_first(n, o) \
	ps_outbuf = ps_midbuf = (char*)malloc(o_proc); \
	cd_struct->cconv_cd = n; \
	if((i_proc = cconv(cd, inbuf, inbytesleft, &ps_outbuf, &o_proc)) == -1) { \
		free(ps_midbuf); return (size_t)(-1); \
	} \
	cd_struct->cconv_cd = o; \

#define cconv_iconv_second(c) \
	ps_outbuf = *outbuf; \
	ps_inbuf  = ps_midbuf; \
	iconvctl(c, ICONV_SET_DISCARD_ILSEQ, &one); \
	if(iconv_wrapper(c, &ps_inbuf, &i_proc, outbuf, outbytesleft) == -1) { \
		free(ps_midbuf); return (size_t)(-1); \
	} \
	free(ps_midbuf); \
	return *outbuf - ps_outbuf;

#define const_bin_c_str(x) (const unsigned char*)(x)

#define EMPTY_END_SIZE 8

/* {{{ size_t cconv() */
/**
 * Convert character code.
 *
 * @param   in_charset	Cconv input charset.
 * @param   out_charset	Cconv output charset.
 * @param   inbuf	   Input buffer.
 * @param   inbytesleft Input buffer left.
 * @retval  t_handle	Cconv handle,(-1: error).
 */
size_t cconv(cconv_t cd,
#ifdef FreeBSD
		const char** inbuf,
#else
		char** inbuf,
#endif
		size_t* inbytesleft,
		char**  outbuf,
		size_t* outbytesleft)
{
	size_t  i_proc = 0, o_proc = 0, m_proc = 0;
#ifdef FreeBSD
	const char *ps_inbuf  = NULL;
#else
	char *ps_inbuf = NULL;
#endif
	char *ps_midbuf, *ps_outbuf = NULL;
	language_zh_map *m;
	int map_size;
	int one = 1;

	if(NULL == inbuf  || NULL == *inbuf  || NULL == inbytesleft || NULL == outbuf || NULL == *outbuf || NULL == outbytesleft)
		return(size_t)(-1);

	cconv_struct *cd_struct = cd;
	ps_inbuf  = *inbuf;
	ps_outbuf = *outbuf;
	o_proc    = cd_struct->size_factor * (*inbytesleft) + EMPTY_END_SIZE;
	m_proc    = o_proc;

	if((cconv_t)(CCONV_ERROR) == cd)
		return(size_t)(-1);

	switch(cd_struct->cconv_cd)
	{
	case CCONV_UTF_TO_UHT:
	case CCONV_UTF_TO_UHS:
		m        = zh_map     (cd_struct->cconv_cd);
		map_size = zh_map_size(cd_struct->cconv_cd);
		return cconv_utf8((const char**)inbuf, inbytesleft, outbuf, outbytesleft, m, map_size);

	case CCONV_UTF_TO_GBL:
		cconv_cconv_first(CCONV_UTF_TO_UHS, CCONV_UTF_TO_GBL);
		cconv_iconv_second(cd_struct->utf8_gb);

	case CCONV_UTF_TO_GHT:
		cconv_cconv_first(CCONV_UTF_TO_UHT, CCONV_UTF_TO_GHT);
		cconv_iconv_second(cd_struct->utf8_gb);

	case CCONV_UTF_TO_BIG:
		cconv_cconv_first(CCONV_UTF_TO_UHT, CCONV_UTF_TO_BIG);
		cconv_iconv_second(cd_struct->utf8_bg);

	case CCONV_GBL_TO_UHT:
		cconv_iconv_first(cd_struct->gb_utf8);
		cconv_cconv_second(CCONV_UTF_TO_UHT, CCONV_GBL_TO_UHT);

	case CCONV_GBL_TO_UHS:
		cconv_iconv_first(cd_struct->gb_utf8);
		cconv_cconv_second(CCONV_UTF_TO_UHS, CCONV_GBL_TO_UHS);

	case CCONV_GBL_TO_BIG:
		cconv_cconv_first(CCONV_GBL_TO_UHT, CCONV_GBL_TO_BIG);
		cconv_iconv_second(cd_struct->utf8_bg);

	case CCONV_GBL_TO_GHS:
		cconv_cconv_first(CCONV_GBL_TO_UHS, CCONV_GBL_TO_GHS);
		cconv_iconv_second(cd_struct->utf8_gb);

	case CCONV_GBL_TO_GHT:
		cconv_cconv_first(CCONV_GBL_TO_UHT, CCONV_GBL_TO_GHT);
		cconv_iconv_second(cd_struct->utf8_gb);

	case CCONV_BIG_TO_UHS:
		cconv_iconv_first(cd_struct->bg_utf8);
		cconv_cconv_second(CCONV_UTF_TO_UHS, CCONV_BIG_TO_UHS);

	case CCONV_BIG_TO_GBL:
		cconv_cconv_first(CCONV_BIG_TO_UHS, CCONV_BIG_TO_GBL);
		cconv_iconv_second(cd_struct->utf8_gb);

	case CCONV_NULL:
	default:
		break;
	} // switch

	ps_outbuf = *outbuf;
	iconvctl(cd_struct->iconv_cd, ICONV_SET_DISCARD_ILSEQ, &one);
	if(iconv_wrapper(cd_struct->iconv_cd, inbuf, inbytesleft, outbuf, outbytesleft) == -1)
		return (size_t)(-1);

	return *outbuf - ps_outbuf;
}
/* }}} */

/* {{{ int cconv_close( cconv_t cd ) */
/**
 * Close a cconv handle.
 *
 * @param   cd          Cconv handle.
 * @return              0: succ, -1: fail.
 */
int cconv_close(cconv_t cd)
{
	cconv_struct *c = cd;
	if(c->iconv_cd && (iconv_t)(-1) != c->iconv_cd) iconv_close(c->iconv_cd);
	if(c->gb_utf8  && (iconv_t)(-1) != c->gb_utf8 ) iconv_close(c->gb_utf8 );
	if(c->bg_utf8  && (iconv_t)(-1) != c->bg_utf8 ) iconv_close(c->bg_utf8 );
	if(c->utf8_gb  && (iconv_t)(-1) != c->utf8_gb ) iconv_close(c->utf8_gb );
	if(c->utf8_bg  && (iconv_t)(-1) != c->utf8_bg ) iconv_close(c->utf8_bg );
	free(c);
	return 0;
}
/* }}} */

size_t cconv_utf8(const char** inbuf, size_t* inleft, char** outbuf, size_t* outleft, const language_zh_map *m, int map_size)
{
	const char *ps_inbuf;
	char *ps_outbuf;
	int index;
	size_t i_proc, o_proc, i_conv = 0, o_conv;

	ps_inbuf  = *inbuf;
	ps_outbuf = *outbuf;
	for (; *inleft > 0 && *outleft > 0; )
	{
		if((i_proc = utf8_char_width(const_bin_c_str(ps_inbuf))) > *inleft)
			break;

		if(i_proc > 1 &&
		  (index = find_keyword(ps_inbuf, &i_proc, *inleft, m, 0, map_size - 1, i_conv)) != -1)
		{
			o_proc = strlen(map_val(m, index));
			memcpy(ps_outbuf, map_val(m, index), o_proc);
			ps_inbuf  += i_proc;
			ps_outbuf += o_proc;
			*inleft   -= i_proc;
			*outleft  -= o_proc;
			i_conv    += i_proc;
			continue;
		}

		if(i_proc == -1)
		{
			errno  = EINVAL;
			return (size_t)(-2);
		}

		memcpy(ps_outbuf, ps_inbuf, i_proc);
		ps_inbuf  += i_proc;
		ps_outbuf += i_proc;
		*inleft   -= i_proc;
		*outleft  -= i_proc;
		i_conv    += i_proc;
	}

	o_conv = ps_outbuf - *outbuf;
	*ps_outbuf = '\0';
	*inbuf  = ps_inbuf;
	*outbuf = ps_outbuf;
	return o_conv;
}

int find_keyword(const char* inbytes, size_t* length, size_t max_length, const language_zh_map *m, int begin, int end, const int whence)
{
	int location;

	if((location = binary_find(inbytes, length, max_length, m, begin, end)) == -1)
		return -1;

	/* extention word fix */
	if(!match_cond(cond_ptr(m, location), inbytes, strlen(map_key(m, location)), whence))
	{
		*length = utf8_char_width(const_bin_c_str(inbytes));
		return -1;
	}

	return location;
}

int _find_range(const char *inbytes, size_t length, const language_zh_map *m,
				int begin, int end, int *range_begin, int *range_end, int *max_key_length)
{
	// binary_search
	int low = begin;
	int high = end;
	int middle;
	while (1)
	{
		if (low > high)
		{
			return 0;
		}

		middle = (low + high) >> 1;
		int ret = memcmp(m[middle].key, inbytes, length);
		if (ret == 0)
		{
			break;
		}
		else if (ret > 0)
		{
			high = middle - 1;
		}
		else /* if (ret < 0) */
		{
			low = middle + 1;
		}
	}

	// find range begin
	int rbegin = middle;
	while (rbegin > begin &&
		   memcmp(m[rbegin - 1].key, inbytes, length) == 0)
	{
		rbegin--;
	}
	*range_begin = rbegin;

	// find range end
	int rend = middle;
	while (rend < end &&
		   memcmp(m[rend+ 1].key, inbytes, length) == 0)
	{
		rend++;
	}
	*range_end = rend;

	// get max key length
	int i;
	*max_key_length = 0;
	for (i = rbegin; i <= rend; i++)
	{
		size_t key_length = strlen(m[i].key);
		if (key_length > *max_key_length)
		{
			*max_key_length = key_length;
		}
	}

	return rend - rbegin + 1;
}

int _find_exact(const char *inbytes, size_t length, const language_zh_map *m, int begin, int end)
{
	// binary_search
	int low = begin;
	int high = end;
	int middle;
	while (1)
	{
		if (low > high)
		{
			return -1;
		}

		middle = (low + high) >> 1;
		int ret = memcmp(m[middle].key, inbytes, length);
		if (ret == 0)
		{
			int key_length = strlen(m[middle].key);
			if (key_length == length)
			{
				return middle;
			}
			ret = key_length - length;
		}

		if (ret > 0)
		{
			high = middle - 1;
		}
		else /* if (ret < 0) */
		{
			low = middle + 1;
		}
	}
}

int binary_find(const char* inbytes, size_t* length, size_t max_length, const language_zh_map *m, int begin, int end)
{
	int range_begin, range_end, max_key_length;
	int result, index;
	int word_length;

	// find range
	if (_find_range(inbytes, *length, m, begin, end, &range_begin, &range_end, &max_key_length) <= 0)
	{
		return -1;
	}

	// word match
	result = -1;
	word_length = *length;
	while (word_length <= max_key_length && word_length <= max_length)
	{
		index = _find_exact(inbytes, word_length, m, range_begin, range_end);
		if (index != -1)
		{
			*length = word_length;
			result = index;
			range_begin = index + 1;
		}
		word_length += utf8_char_width(const_bin_c_str(inbytes + word_length));
	}

	return result;
}

int match_cond(const factor_zh_map *cond, const char* str, int klen, const int whence)
{
	int y_ma, y_mb;
	const char *cond_str = NULL;
	const char *y_a_null, *y_b_null;

	cond_str = cond_c_str(cond, n_ma);
	if(cond_str && match_real_cond(cond_str , str + klen, 0, whence))
		return 0;

	cond_str = cond_c_str(cond, n_mb);
	if(cond_str && match_real_cond(cond_str , str, 1, whence))
		return 0;

	y_b_null = cond_str = cond_c_str(cond, y_mb);
	y_ma = cond_str && match_real_cond(cond_str, str, 1, whence);

	y_a_null = cond_str = cond_c_str(cond, y_ma);
	y_mb = cond_str && match_real_cond(cond_str, str + klen, 0, whence);
	return (!y_b_null&&!y_a_null) | y_ma | y_mb;
}

int match_real_cond(const char* mc, const char* str, int head, const int whence)
{
	int size;
	char *m_one, *p;

	size = strlen(mc);
	p = (char *)malloc(size + 1);
	memcpy(p, mc, size);
	p[size] = '\0';

	m_one = strtok(p, ",");
	while(m_one)
	{
		if((head == 1 && whence >= strlen(m_one) &&
			memcmp(str - strlen(m_one), m_one, strlen(m_one)) == 0)
		 ||(head == 0 && strlen(str) >= strlen(m_one) &&
			memcmp(str, m_one, strlen(m_one)) == 0)
		){
			free(p);
			return 1;
		}

		m_one = strtok(NULL, ",");
	}

	free(p);
	return 0;
}

